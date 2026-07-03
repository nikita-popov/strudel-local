#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-./samples}"
DOUGH_REPO="https://github.com/felixroos/dough-samples.git"
UZU_DRUMKIT_REPO="https://github.com/tidalcycles/uzu-drumkit.git"
UZU_WAVETABLES_REPO="https://github.com/tidalcycles/uzu-wavetables.git"

mkdir -p "$OUT_DIR"

clone_or_update() {
	local repo_url="$1"
	local dest="$2"
	if [ -d "$dest/.git" ]; then
		echo "Updating $dest..."
		git -C "$dest" pull --recurse-submodules
		git -C "$dest" submodule update --init --recursive
	else
		echo "Cloning $repo_url -> $dest..."
		git clone --depth 1 --recurse-submodules "$repo_url" "$dest"
	fi
}

clone_or_update "$DOUGH_REPO" "$OUT_DIR"
clone_or_update "$UZU_DRUMKIT_REPO" "$OUT_DIR/uzu-drumkit"
clone_or_update "$UZU_WAVETABLES_REPO" "$OUT_DIR/uzu-wavetables"

# Expose manifests at the root, whatever their name is inside each repo
find "$OUT_DIR/uzu-drumkit" -maxdepth 1 -iname "*.json" -exec cp {} "$OUT_DIR/uzu-drumkit.json" \; 2>/dev/null || true
find "$OUT_DIR/uzu-wavetables" -maxdepth 1 -iname "*.json" -exec cp {} "$OUT_DIR/uzu-wavetables.json" \; 2>/dev/null || true

echo ""
echo "Done. Local samples root: $OUT_DIR"
find "$OUT_DIR" -maxdepth 1 -iname "*.json"
