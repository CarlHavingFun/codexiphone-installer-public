#!/usr/bin/env bash
set -euo pipefail

DEFAULT_MANIFEST_URL="https://product.example.com/codexiphone/runtime-manifest.json"
MANIFEST_URL="${CODEXIPHONE_MANIFEST_URL:-$DEFAULT_MANIFEST_URL}"
RUNTIME_TARBALL_URL="${CODEXIPHONE_RUNTIME_TARBALL_URL:-}"
RUNTIME_TARBALL_SHA256="${CODEXIPHONE_RUNTIME_TARBALL_SHA256:-}"
INSTALL_ROOT="${CODEXIPHONE_INSTALL_ROOT:-$HOME/.codexiphone}"
PROJECT_DIR="${INSTALL_ROOT%/}/codexiphone-runtime"

log() {
  echo "[codexiphone-install] $*"
}

print_network_hint() {
  local target="${1:-unknown}"
  echo "[codexiphone-install] HINT: network access may be blocked or timing out: $target" >&2
  echo "[codexiphone-install] HINT: if you are on a restricted network, enable VPN/proxy and retry." >&2
}

need_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return
  fi
  echo "[codexiphone-install] ERROR: missing command: $cmd" >&2
  exit 1
}

trim_line_breaks() {
  tr -d '\r\n'
}

json_get_string() {
  local key="$1"
  local input="$2"
  printf '%s' "$input" | trim_line_breaks | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

sha256_file() {
  local file_path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file_path" | awk '{print $NF}'
    return 0
  fi
  return 1
}

resolve_runtime_bundle_from_manifest_if_needed() {
  if [[ -n "$RUNTIME_TARBALL_URL" ]]; then
    return
  fi

  log "resolving runtime bundle via manifest: $MANIFEST_URL"
  local manifest_json
  if ! manifest_json="$(curl -fsSL --connect-timeout 15 --max-time 30 "$MANIFEST_URL")"; then
    print_network_hint "$MANIFEST_URL"
    echo "[codexiphone-install] ERROR: failed to fetch runtime manifest" >&2
    exit 1
  fi

  RUNTIME_TARBALL_URL="$(json_get_string "tarball_url" "$manifest_json")"
  RUNTIME_TARBALL_SHA256="${RUNTIME_TARBALL_SHA256:-$(json_get_string "sha256_tar_gz" "$manifest_json")}"

  if [[ -z "$RUNTIME_TARBALL_URL" ]]; then
    echo "[codexiphone-install] ERROR: invalid manifest (missing tarball_url)" >&2
    exit 1
  fi
}

verify_runtime_checksum_if_available() {
  local file_path="$1"
  local expected="${2:-}"
  if [[ -z "$expected" ]]; then
    log "checksum skipped (manifest sha256_tar_gz not provided)"
    return
  fi

  local actual
  if ! actual="$(sha256_file "$file_path")"; then
    log "checksum skipped (sha256 tool unavailable)"
    return
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "[codexiphone-install] ERROR: runtime checksum mismatch" >&2
    echo "[codexiphone-install] expected=$expected" >&2
    echo "[codexiphone-install] actual=$actual" >&2
    exit 1
  fi

  log "checksum verified"
}

looks_like_cloud_or_server_runtime() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files --type=service 2>/dev/null | grep -Eq '^codex-(relay|platform-api|otp-dispatcher)\.service'; then
      return 0
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    if NO_PROXY=100.100.100.200,no_proxy=100.100.100.200 \
      curl -fsS --max-time 1 "http://100.100.100.200/latest/meta-data/instance-id" >/dev/null 2>&1; then
      return 0
    fi
  fi

  return 1
}

install_runtime_bundle() {
  local tmp_tar
  tmp_tar="$(mktemp)"

  resolve_runtime_bundle_from_manifest_if_needed

  mkdir -p "$INSTALL_ROOT"
  log "downloading runtime bundle: $RUNTIME_TARBALL_URL"
  if ! curl -fL --connect-timeout 15 --max-time 180 "$RUNTIME_TARBALL_URL" -o "$tmp_tar"; then
    rm -f "$tmp_tar"
    print_network_hint "$RUNTIME_TARBALL_URL"
    exit 1
  fi

  verify_runtime_checksum_if_available "$tmp_tar" "$RUNTIME_TARBALL_SHA256"

  if [[ -d "$PROJECT_DIR" ]]; then
    rm -rf "$PROJECT_DIR"
  fi

  if ! tar -xzf "$tmp_tar" -C "$INSTALL_ROOT"; then
    rm -f "$tmp_tar"
    echo "[codexiphone-install] ERROR: failed to extract runtime bundle" >&2
    exit 1
  fi
  rm -f "$tmp_tar"

  if [[ ! -f "$PROJECT_DIR/deploy/agent/quick_guide.sh" ]]; then
    echo "[codexiphone-install] ERROR: invalid runtime bundle layout" >&2
    exit 1
  fi
}

main() {
  need_cmd bash
  need_cmd curl
  need_cmd tar

  if looks_like_cloud_or_server_runtime && [[ -z "${CODEXIPHONE_TARGET:-}" ]]; then
    log "cloud/server runtime detected; installer will auto-resolve target=server"
  fi

  install_runtime_bundle
  cd "$PROJECT_DIR"

  log "starting quick guide installer"
  if ! bash "$PROJECT_DIR/deploy/agent/quick_guide.sh" "$@"; then
    print_network_hint "${PLATFORM_BASE_URL:-https://product.example.com/codex-platform}"
    exit 1
  fi
}

main "$@"
