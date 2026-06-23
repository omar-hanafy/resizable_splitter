#!/usr/bin/env bash
#
# Builds the resizable_splitter showcase and syncs it into the GitHub Pages
# repo folder. Regenerates the package metadata first (see
# tool/gen_package_meta.dart), so the deployed site always reflects the
# package's current pubspec version and links - no manual edits per release.
#
# Usage:
#   tool/deploy.sh [dest-folder]
#
# dest-folder defaults to ../../omar-hanafy.github.io/resizable-splitter, the
# GitHub Pages repo checked out alongside this package. Review the diff and
# commit/push the Pages repo yourself afterwards.
set -euo pipefail

cd "$(dirname "$0")/.." # -> example/

base_href="/resizable-splitter/"
dest="${1:-../../omar-hanafy.github.io/resizable-splitter}"

echo "==> Regenerating package metadata from ../pubspec.yaml"
dart run tool/gen_package_meta.dart

echo "==> flutter build web --wasm --base-href $base_href"
flutter build web --wasm --base-href "$base_href"

echo "==> Syncing build/web/ -> $dest/"
mkdir -p "$dest"
rsync -a --delete \
  --exclude '.git' --exclude 'CNAME' --exclude '.nojekyll' \
  build/web/ "$dest/"

echo "==> Done. Review and publish the Pages repo:"
echo "    cd \"$dest\" && git add -A && git commit -m 'deploy: resizable_splitter showcase' && git push"
