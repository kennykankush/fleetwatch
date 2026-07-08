#!/bin/sh
# Fleetwatch installer. Downloads the notarized app from GitHub Releases and
# installs it to /Applications (or ~/Applications if /Applications isn't writable).
#
#   curl -fsSL https://raw.githubusercontent.com/kennykankush/fleetwatch/main/scripts/install.sh | sh
#
# Env:
#   STOCKPILE_VERSION       version tag to install (default: latest, e.g. v0.1.0)
#   STOCKPILE_INSTALL_DIR   install directory (default: /Applications)
set -eu

REPO="kennykankush/fleetwatch"
APP="Fleetwatch.app"

say() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "required tool not found: $1"; }
need curl

[ "$(uname -s)" = "Darwin" ] || err "Fleetwatch is a macOS app (this is $(uname -s))"

# --- resolve version ------------------------------------------------------
VERSION="${STOCKPILE_VERSION:-latest}"
if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
  [ -n "$VERSION" ] || err "couldn't resolve the latest release tag"
fi
BARE_VERSION="${VERSION#v}"
URL="https://github.com/$REPO/releases/download/$VERSION/Fleetwatch-$BARE_VERSION.zip"

# --- pick install dir -----------------------------------------------------
INSTALL_DIR="${STOCKPILE_INSTALL_DIR:-/Applications}"
if [ ! -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
  say "note: /Applications not writable — installing to $INSTALL_DIR"
fi

# --- download + install ---------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "downloading Fleetwatch $VERSION…"
curl -fsSL -o "$TMP/fleetwatch.zip" "$URL" || err "download failed: $URL"

say "unpacking…"
ditto -x -k "$TMP/fleetwatch.zip" "$TMP/unpacked" || err "unzip failed"
[ -d "$TMP/unpacked/$APP" ] || err "archive did not contain $APP"

if [ -d "$INSTALL_DIR/$APP" ]; then
  say "replacing existing $INSTALL_DIR/$APP…"
  rm -rf "$INSTALL_DIR/$APP"
fi
ditto "$TMP/unpacked/$APP" "$INSTALL_DIR/$APP"

say "✅ installed: $INSTALL_DIR/$APP (notarized — opens with no warnings)"
say "   open -a Fleetwatch"
