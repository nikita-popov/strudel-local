#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-./samples}"
REPO_URL="https://github.com/felixroos/dough-samples.git"

mkdir -p "$OUT_DIR"

if [ -d "$OUT_DIR/.git" ]; then
    echo "Repo already cloned, updating..."
    git -C "$OUT_DIR" pull --recurse-submodules
    git -C "$OUT_DIR" submodule update --init --recursive
else
    echo "Cloning dough-samples (with submodules)..."
    git clone --recurse-submodules "$REPO_URL" "$OUT_DIR"
fi

echo ""
echo "Done. Local samples root: $OUT_DIR"
echo "Manifests available: piano.json, vcsl.json, tidal-drum-machines.json, Dirt-Samples.json, EmuSP12.json, mridangam.json"
