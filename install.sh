#!/bin/bash
set -euo pipefail

# Cellar installer — https://github.com/lasermaze/Cellar
# Usage: curl -fsSL https://raw.githubusercontent.com/lasermaze/Cellar/main/install.sh | bash

if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  BOLD=''
  RESET=''
fi

info()    { printf "${BOLD}==> %s${RESET}\n" "$*"; }
success() { printf "${GREEN}==> %s${RESET}\n" "$*"; }
error()   { printf "${RED}error: %s${RESET}\n" "$*" >&2; }

# Step 1 — OS detection
if [ "$(uname -s)" != "Darwin" ]; then
  error "Cellar requires macOS. Detected: $(uname -s)"
  exit 1
fi

# Step 2 — Architecture detection
ARCH=$(uname -m)

# Step 3 — Version resolution
INSTALL_DIR="${CELLAR_INSTALL_DIR:-$HOME/.cellar/bin}"

if [ -n "${CELLAR_VERSION:-}" ]; then
  VERSION="$CELLAR_VERSION"
else
  info "Fetching latest Cellar release..."
  API_RESPONSE=$(curl -fsSL "https://api.github.com/repos/lasermaze/Cellar/releases/latest" 2>/dev/null || echo "")
  VERSION=$(echo "$API_RESPONSE" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"//;s/"//' || echo "")
  if [ -z "$VERSION" ]; then
    error "Could not determine latest version from GitHub API."
    error "This may mean no release has been published yet."
    error "Check: https://github.com/lasermaze/Cellar/releases"
    exit 1
  fi
fi

VERSION_NUM="${VERSION#v}"
if [[ "$VERSION" != v* ]]; then
  VERSION="v$VERSION"
fi

# Step 4 — Download to temp directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ARCHIVE="cellar-${VERSION_NUM}-macos.tar.gz"
BASE_URL="https://github.com/lasermaze/Cellar/releases/download/${VERSION}"

info "Downloading Cellar ${VERSION} (${ARCH})..."
curl -fSL "${BASE_URL}/${ARCHIVE}" -o "$TMPDIR/$ARCHIVE"

# Step 5 — Checksum verification
if curl -fsSL "${BASE_URL}/${ARCHIVE}.sha256" -o "$TMPDIR/${ARCHIVE}.sha256" 2>/dev/null; then
  info "Verifying checksum..."
  (cd "$TMPDIR" && shasum -a 256 -c "${ARCHIVE}.sha256")
else
  printf "warning: checksum file not available, skipping verification\n"
fi

# Step 6 — Install binary
info "Installing to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/$ARCHIVE" -C "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/cellar"

# Step 7 — Remove quarantine (binary + resource bundle)
xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar" 2>/dev/null || true
xattr -rd com.apple.quarantine "$INSTALL_DIR/cellar_cellar.bundle" 2>/dev/null || true

# Step 8 — PATH update (idempotent)
case "$SHELL" in
  */zsh)  RC="$HOME/.zshrc" ;;
  */bash) RC="$HOME/.bash_profile" ;;
  *)      RC="$HOME/.profile" ;;
esac

if ! grep -qF 'cellar/bin' "$RC" 2>/dev/null; then
  printf '\nexport PATH="$HOME/.cellar/bin:$PATH"\n' >> "$RC"
  info "Added ~/.cellar/bin to PATH in ${RC}"
fi

# Step 9 — Smoke test (--help exits non-zero with ArgumentParser, so check output instead)
SMOKE_OUTPUT=$("$INSTALL_DIR/cellar" --help 2>&1 || true)
if ! echo "$SMOKE_OUTPUT" | grep -q "cellar"; then
  error "Smoke test failed. Try: xattr -rd com.apple.quarantine '$INSTALL_DIR/cellar'"
  error "Or check System Settings > Privacy & Security and allow the binary."
  exit 1
fi

# Step 10 — Success message
success "Cellar ${VERSION} installed successfully!"
printf "\n"
printf "  ${BOLD}Version:${RESET}  %s\n" "$VERSION"
printf "  ${BOLD}Arch:${RESET}     %s\n" "$ARCH"
printf "  ${BOLD}Location:${RESET} %s/cellar\n" "$INSTALL_DIR"
printf "\n"
printf "\n"
printf "  ${BOLD}Next: run these two commands to get started:${RESET}\n"
printf "\n"
printf "    source %s\n" "$RC"
printf "    cellar serve\n"
printf "\n"
printf "  This opens Cellar in your browser where you can\n"
printf "  set up your API key, install Wine, add games,\n"
printf "  and launch them — all from the UI.\n"
printf "\n"
