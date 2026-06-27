#!/usr/bin/env bash
#
# AgentChain one-command installer (Linux & macOS)
#
#   curl -fsSL https://get.agentchain.app | bash
#
# Downloads the latest release from GitHub, verifies its SHA-256 checksum
# against the published SHA256SUMS file, and installs it.
#
# Asset naming contract (must match the release builder exactly):
#   Linux : AgentChain-${version}.AppImage   /  agentchain_${version}_amd64.deb
#   macOS : AgentChain-${version}-x64.dmg     /  AgentChain-${version}-arm64.dmg
#
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
REPO="DiegoGaxi/agentchain-releases"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# ── Pretty output ───────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""
fi

info()  { printf '%s\n' "${CYAN}::${RESET} $*"; }
ok()    { printf '%s\n' "${GREEN}✓${RESET} $*"; }
warn()  { printf '%s\n' "${YELLOW}!${RESET} $*" >&2; }
err()   { printf '%s\n' "${RED}✗ $*${RESET}" >&2; }
die()   { err "$@"; exit 1; }

banner() {
  printf '%s\n' "${BOLD}${CYAN}"
  printf '%s\n' "   _                    _    ____ _           _       "
  printf '%s\n' "  /_\\  __ _ ___ _ _| |_ / ___| |__   __ _(_)_ _  "
  printf '%s\n' " / _ \\/ _\` / -_) ' \\  _| (__| ' \\ / _\` | | ' \\ "
  printf '%s\n' "/_/ \\_\\__, \\___|_||_\\__|\\___|_||_\\__,_|_|_||_|"
  printf '%s\n' "      |___/                                          "
  printf '%s\n' "${RESET}${DIM}        one-command installer${RESET}"
  printf '\n'
}

# ── Dependency helpers ──────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }

require() {
  have "$1" || die "Required command '$1' is not installed."
}

# Pick an available HTTP downloader.
DOWNLOADER=""
if have curl; then
  DOWNLOADER="curl"
elif have wget; then
  DOWNLOADER="wget"
else
  die "Need either 'curl' or 'wget' to download files."
fi

# fetch <url> -> stdout
fetch() {
  if [ "$DOWNLOADER" = "curl" ]; then
    curl -fsSL "$1"
  else
    wget -qO- "$1"
  fi
}

# download <url> <dest>
download() {
  local url="$1" dest="$2"
  info "Downloading $(basename "$dest") ..."
  if [ "$DOWNLOADER" = "curl" ]; then
    curl -fSL --progress-bar "$url" -o "$dest"
  else
    wget -q --show-progress -O "$dest" "$url"
  fi
}

# ── Platform detection ──────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux"  ;;
    Darwin*) echo "darwin" ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)        echo "x86_64" ;;
    arm64|aarch64)       echo "arm64"  ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# ── GitHub release metadata ─────────────────────────────────────────────────
RELEASE_JSON=""
load_release() {
  info "Querying latest release from ${REPO} ..."
  RELEASE_JSON="$(fetch "$API_URL")" \
    || die "Could not reach the GitHub release API."
  [ -n "$RELEASE_JSON" ] || die "Empty response from GitHub release API."
}

# release_tag -> the tag name, e.g. v1.2.3
release_tag() {
  if have jq; then
    printf '%s' "$RELEASE_JSON" | jq -r '.tag_name // empty'
  else
    printf '%s' "$RELEASE_JSON" \
      | grep -m1 '"tag_name"' \
      | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  fi
}

# asset_url <asset-name> -> browser_download_url for an exact asset name
asset_url() {
  local name="$1"
  if have jq; then
    printf '%s' "$RELEASE_JSON" \
      | jq -r --arg n "$name" \
        '.assets[] | select(.name == $n) | .browser_download_url' \
      | head -n1
  else
    # Walk the JSON looking for the browser_download_url whose path ends in
    # exactly the asset name. Newlines are inserted before each URL key so
    # grep can isolate one candidate per line.
    printf '%s' "$RELEASE_JSON" \
      | tr ',' '\n' \
      | grep '"browser_download_url"' \
      | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
      | grep -E "/${name}$" \
      | head -n1
  fi
}

# ── Checksum verification ───────────────────────────────────────────────────
# verify_checksum <file> <asset-name> <sha256sums-file>
# Returns 0 if verified, 1 if mismatch, 2 if no entry / cannot verify.
verify_checksum() {
  local file="$1" name="$2" sums="$3"
  local expected actual sha_cmd

  expected="$(grep -E "[[:space:]]\*?${name}\$" "$sums" 2>/dev/null \
              | head -n1 | awk '{print $1}')"
  [ -n "$expected" ] || return 2

  if have sha256sum; then
    sha_cmd="sha256sum"
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif have shasum; then
    sha_cmd="shasum -a 256"
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    return 2
  fi

  if [ "$expected" = "$actual" ]; then
    return 0
  fi
  return 1
}

# ── Install: Linux ──────────────────────────────────────────────────────────
install_linux() {
  local version="$1"
  local appimage="AgentChain-${version}.AppImage"
  local url
  url="$(asset_url "$appimage")"

  [ -n "$url" ] || die "No AppImage named '${appimage}' in release ${version}.
Available assets did not include the expected Linux build."

  local tmp
  tmp="$(mktemp -d)"
  # Guard with ${tmp:-}: a RETURN trap set in a function persists and also fires
  # on main()'s return (where this local is out of scope) → under `set -u` that
  # raised "tmp: unbound variable" after a successful install. The :- makes it safe.
  trap 'rm -rf "${tmp:-}"' RETURN
  local out="${tmp}/${appimage}"

  download "$url" "$out"

  # Verify against the per-platform SHA256SUMS file (best-effort, non-fatal if absent).
  local sums_url sums_file
  sums_url="$(asset_url "SHA256SUMS-linux.txt")"
  if [ -n "$sums_url" ]; then
    sums_file="${tmp}/SHA256SUMS"
    if fetch "$sums_url" > "$sums_file" 2>/dev/null; then
      if verify_checksum "$out" "$appimage" "$sums_file"; then
        ok "Checksum verified."
      else
        case $? in
          1) die "Checksum MISMATCH for ${appimage}. Aborting for safety." ;;
          *) warn "Could not verify checksum (no entry / no tool). Continuing." ;;
        esac
      fi
    else
      warn "Could not download SHA256SUMS. Skipping verification."
    fi
  else
    warn "Release has no SHA256SUMS asset. Skipping verification."
  fi

  # Choose an install location: prefer a writable ~/.local/bin (no sudo),
  # fall back to /usr/local/bin via sudo if the home directory is unusable.
  local bindir target used_sudo=0
  bindir="${HOME}/.local/bin"
  if ! mkdir -p "$bindir" 2>/dev/null; then
    if have sudo; then
      bindir="/usr/local/bin"
      sudo mkdir -p "$bindir"
      used_sudo=1
    else
      die "Cannot create ${HOME}/.local/bin and sudo is unavailable."
    fi
  fi
  target="${bindir}/AgentChain.AppImage"

  if [ "$used_sudo" -eq 1 ]; then
    sudo install -m 0755 "$out" "$target"
  else
    install -m 0755 "$out" "$target" 2>/dev/null || {
      cp "$out" "$target" && chmod +x "$target"
    }
  fi
  ok "Installed to ${BOLD}${target}${RESET}"

  # Create a .desktop entry for menu launchers.
  local apps_dir="${HOME}/.local/share/applications"
  mkdir -p "$apps_dir"
  local desktop="${apps_dir}/agentchain.desktop"
  cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AgentChain
Comment=AgentChain desktop app
Exec=${target} %U
Icon=agentchain
Terminal=false
Categories=Development;Utility;
StartupWMClass=AgentChain
EOF
  chmod 0644 "$desktop"
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  ok "Created desktop entry: ${desktop}"

  printf '\n'
  ok "${BOLD}AgentChain ${version} installed!${RESET}"
  info "Launch it from your app menu, or run:"
  printf '    %s\n' "${BOLD}${target}${RESET}"
  case ":${PATH}:" in
    *":${bindir}:"*) : ;;
    *) warn "${bindir} is not on your PATH. Add it with:"
       printf '    %s\n' "export PATH=\"${bindir}:\$PATH\"" ;;
  esac
}

# ── Install: macOS ──────────────────────────────────────────────────────────
install_macos() {
  local version="$1" arch="$2"
  local dmg_arch
  case "$arch" in
    x86_64) dmg_arch="x64"   ;;
    arm64)  dmg_arch="arm64" ;;
    *) die "Unsupported macOS architecture: $arch" ;;
  esac

  local dmg="AgentChain-${version}-${dmg_arch}.dmg"
  local url
  url="$(asset_url "$dmg")"

  [ -n "$url" ] || die "No disk image named '${dmg}' in release ${version}.
Available assets did not include the expected macOS (${dmg_arch}) build."

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN
  local out="${tmp}/${dmg}"

  download "$url" "$out"

  # Verify against the per-platform SHA256SUMS file (mac builds are arm64-only).
  local sums_url sums_file
  sums_url="$(asset_url "SHA256SUMS-mac-arm64.txt")"
  if [ -n "$sums_url" ]; then
    sums_file="${tmp}/SHA256SUMS"
    if fetch "$sums_url" > "$sums_file" 2>/dev/null; then
      if verify_checksum "$out" "$dmg" "$sums_file"; then
        ok "Checksum verified."
      else
        case $? in
          1) die "Checksum MISMATCH for ${dmg}. Aborting for safety." ;;
          *) warn "Could not verify checksum (no entry / no tool). Continuing." ;;
        esac
      fi
    else
      warn "Could not download SHA256SUMS. Skipping verification."
    fi
  else
    warn "Release has no SHA256SUMS asset. Skipping verification."
  fi

  # Mount the DMG, copy the app, then detach.
  info "Mounting disk image ..."
  local mountpoint
  mountpoint="$(mktemp -d "${tmp}/mnt.XXXXXX")"
  hdiutil attach "$out" -nobrowse -quiet -mountpoint "$mountpoint" \
    || die "Failed to mount ${dmg}."

  # shellcheck disable=SC2064
  trap "hdiutil detach '$mountpoint' -quiet >/dev/null 2>&1 || true; rm -rf '$tmp'" RETURN

  local app_src
  app_src="$(find "$mountpoint" -maxdepth 1 -name '*.app' -print -quit)"
  [ -n "$app_src" ] || die "No .app bundle found inside ${dmg}."

  local app_name dest
  app_name="$(basename "$app_src")"
  dest="/Applications/${app_name}"

  info "Installing ${app_name} to /Applications ..."
  rm -rf "$dest" 2>/dev/null || sudo rm -rf "$dest" 2>/dev/null || true
  if cp -R "$app_src" "$dest" 2>/dev/null; then
    :
  else
    warn "Need elevated permissions to write to /Applications."
    sudo cp -R "$app_src" "$dest" || die "Failed to copy app to /Applications."
  fi

  info "Unmounting disk image ..."
  hdiutil detach "$mountpoint" -quiet >/dev/null 2>&1 || true

  # Strip the Gatekeeper quarantine flag — these builds are UNSIGNED.
  info "Removing Gatekeeper quarantine (build is unsigned) ..."
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null \
    || sudo xattr -dr com.apple.quarantine "$dest" 2>/dev/null \
    || warn "Could not clear quarantine; you may need to allow the app in System Settings → Privacy & Security."

  printf '\n'
  ok "${BOLD}AgentChain ${version} installed!${RESET}"
  info "Open it from /Applications or run:"
  printf '    %s\n' "${BOLD}open \"${dest}\"${RESET}"
  printf '\n'
  warn "${BOLD}Note:${RESET} this build is ${BOLD}unsigned${RESET}. If macOS still blocks it,"
  warn "right-click the app → Open, or allow it in System Settings → Privacy & Security."
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  banner

  local os arch version
  os="$(detect_os)"
  arch="$(detect_arch)"
  info "Detected platform: ${BOLD}${os}/${arch}${RESET}"

  load_release
  version="$(release_tag)"
  [ -n "$version" ] || die "Could not determine the latest release tag."
  # The release TAG is v-prefixed (e.g. v2.0.9) but the installer ASSET names use
  # the bare version (AgentChain-2.0.9.AppImage). Strip the leading 'v' so the
  # asset lookups below match.
  version="${version#v}"
  info "Latest release: ${BOLD}v${version}${RESET}"
  printf '\n'

  case "$os" in
    linux)  install_linux  "$version" ;;
    darwin) install_macos  "$version" "$arch" ;;
    *) die "Unsupported OS: $os" ;;
  esac
}

main "$@"
