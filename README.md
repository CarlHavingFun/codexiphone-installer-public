# codexiphone-installer-public

Public installer-only repository for CodexIPhone hosted runtime delivery.

## Scope
- `install.sh`
- `install.ps1`
- `runtime-manifest.template.json`

This repository must not contain iOS source code, Swift files, Xcode project files, or private backend source trees.

## Runtime manifest contract
Production manifest endpoint:
- `https://product.example.com/codexiphone/runtime-manifest.json`

Required fields:
- `version`
- `tarball_url`
- `zip_url`
- `sha256_tar_gz`
- `sha256_zip`
- `published_at`

## Checksum verification
- Unix installer verifies SHA256 when `sha256_tar_gz` is present.
- Windows installer verifies SHA256 when `sha256_zip` is present.

## Policy
Main product repository remains private. External users must install from website runtime artifacts, not from source repositories.
