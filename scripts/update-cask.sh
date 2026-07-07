#!/bin/bash
# Updates Casks/stockpile.rb after a release: version from project.yml,
# sha256 from the built zip. Run after scripts/release.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=$(grep -m1 MARKETING_VERSION project.yml | awk '{print $2}' | tr -d '"')
ZIP="build/Stockpile-$VERSION.zip"
[ -f "$ZIP" ] || { echo "error: $ZIP not found — run scripts/release.sh first" >&2; exit 1; }

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

sed -i '' \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    Casks/stockpile.rb

echo "Casks/stockpile.rb → version $VERSION, sha256 $SHA"
