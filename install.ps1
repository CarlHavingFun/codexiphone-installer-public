param(
  [string]$InstallRoot = "",
  [string]$ManifestUrl = "",
  [string]$RuntimeZipUrl = "",
  [string]$RuntimeZipSha256 = "",
  [string]$PlatformBaseUrl = "",
  [string]$PlatformAccessToken = "",
  [ValidateSet("auto","desktop","server")]
  [string]$Target = "auto"
)

$ErrorActionPreference = "Stop"

if (-not $InstallRoot) {
  if ($env:CODEXIPHONE_INSTALL_ROOT) {
    $InstallRoot = $env:CODEXIPHONE_INSTALL_ROOT
  } else {
    $InstallRoot = Join-Path $HOME ".codexiphone"
  }
}

if (-not $ManifestUrl) {
  if ($env:CODEXIPHONE_MANIFEST_URL) {
    $ManifestUrl = $env:CODEXIPHONE_MANIFEST_URL
  } else {
    $ManifestUrl = "https://product.example.com/codexiphone/runtime-manifest.json"
  }
}

if (-not $RuntimeZipUrl -and $env:CODEXIPHONE_RUNTIME_ZIP_URL) {
  $RuntimeZipUrl = $env:CODEXIPHONE_RUNTIME_ZIP_URL
}

if (-not $RuntimeZipSha256 -and $env:CODEXIPHONE_RUNTIME_ZIP_SHA256) {
  $RuntimeZipSha256 = $env:CODEXIPHONE_RUNTIME_ZIP_SHA256
}

$projectDir = Join-Path $InstallRoot "codexiphone-runtime"

function Write-NetworkHint([string]$TargetUrl) {
  Write-Host "[codexiphone-install] HINT: network access may be blocked or timing out: $TargetUrl"
  Write-Host "[codexiphone-install] HINT: if you are on a restricted network, enable VPN/proxy and retry."
}

function Resolve-RuntimeBundleFromManifestIfNeeded {
  if ($script:RuntimeZipUrl) { return }

  Write-Host "[codexiphone-install] resolving runtime bundle via manifest: $ManifestUrl"
  try {
    $manifestRaw = (Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing -TimeoutSec 30).Content
    $manifest = $manifestRaw | ConvertFrom-Json
  } catch {
    Write-NetworkHint $ManifestUrl
    throw "failed to fetch runtime manifest: $($_.Exception.Message)"
  }

  if (-not $manifest.zip_url) {
    throw "invalid manifest: missing zip_url"
  }

  $script:RuntimeZipUrl = [string]$manifest.zip_url
  if (-not $script:RuntimeZipSha256 -and $manifest.sha256_zip) {
    $script:RuntimeZipSha256 = [string]$manifest.sha256_zip
  }
}

function Verify-RuntimeChecksumIfAvailable([string]$FilePath, [string]$ExpectedSha256) {
  if (-not $ExpectedSha256) {
    Write-Host "[codexiphone-install] checksum skipped (manifest sha256_zip not provided)"
    return
  }

  $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $expected = $ExpectedSha256.ToLowerInvariant()
  if ($actual -ne $expected) {
    throw "runtime checksum mismatch expected=$expected actual=$actual"
  }

  Write-Host "[codexiphone-install] checksum verified"
}

function Install-RuntimeBundle {
  Resolve-RuntimeBundleFromManifestIfNeeded
  New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

  $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) ("codexiphone-runtime-{0}.zip" -f [guid]::NewGuid().ToString("N"))
  Write-Host "[codexiphone-install] downloading runtime bundle: $RuntimeZipUrl"
  try {
    Invoke-WebRequest -Uri $RuntimeZipUrl -UseBasicParsing -OutFile $tempZip -TimeoutSec 180
  } catch {
    Write-NetworkHint $RuntimeZipUrl
    throw "failed to download runtime bundle: $($_.Exception.Message)"
  }

  Verify-RuntimeChecksumIfAvailable -FilePath $tempZip -ExpectedSha256 $RuntimeZipSha256

  if (Test-Path $projectDir) {
    Remove-Item -Path $projectDir -Recurse -Force
  }

  try {
    Expand-Archive -Path $tempZip -DestinationPath $InstallRoot -Force
  } catch {
    throw "failed to extract runtime bundle: $($_.Exception.Message)"
  } finally {
    if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force }
  }

  $quickGuide = Join-Path $projectDir "deploy/agent/quick_guide.ps1"
  if (-not (Test-Path $quickGuide)) {
    throw "invalid runtime bundle layout: $quickGuide"
  }
}

Install-RuntimeBundle

$quickGuide = Join-Path $projectDir "deploy/agent/quick_guide.ps1"
Write-Host "[codexiphone-install] starting quick guide installer"
try {
  & $quickGuide -PlatformBaseUrl $PlatformBaseUrl -PlatformAccessToken $PlatformAccessToken -Target $Target
} catch {
  Write-NetworkHint "$(if ($PlatformBaseUrl) { $PlatformBaseUrl } else { 'https://product.example.com/codex-platform' })"
  throw
}
