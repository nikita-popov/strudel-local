#!/bin/sh
# mirror-assets.sh <dist-dir>
# Download all external URLs found in dist and rewrite references in-place.
# Prefer fixing via patches/ over running this script every build.
set -eu

DIST="${1:-./dist}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

find "$DIST" -type f \( -name '*.html' -o -name '*.js' -o -name '*.mjs' -o -name '*.css' -o -name '*.json' \) > "$TMPDIR/files.list"

python3 - <<'PY' "$TMPDIR/files.list" "$TMPDIR/urls.list"
import re, sys
from pathlib import Path
files = Path(sys.argv[1]).read_text().splitlines()
urls = set()
pat = re.compile(r'(https?://[^"\'\s)><]+|//[^"\'\s)><]+)')
for f in files:
    try:
        text = Path(f).read_text(errors='ignore')
    except Exception:
        continue
    for m in pat.findall(text):
        if m.startswith('//'):
            m = 'https:' + m
        urls.add(m)
Path(sys.argv[2]).write_text('\n'.join(sorted(urls)))
PY

mkdir -p "$DIST/_mirror"
while IFS= read -r url; do
    [ -n "$url" ] || continue
    host="$(printf '%s' "$url" | sed -E 's#https?://([^/]+)/?.*#\1#')"
    path="$(printf '%s' "$url" | sed -E 's#https?://[^/]+/?(.*)#\1#')"
    [ -n "$path" ] || path=index
    target="$DIST/_mirror/$host/$path"
    mkdir -p "$(dirname "$target")"
    curl -L --fail --silent --show-error "$url" -o "$target"
    rel="$(printf '%s' "$target" | sed "s#^$DIST#.#")"
    esc_url="$(printf '%s' "$url" | sed 's/[.[\/\*^$()+?{|]/\\&/g')"
    while IFS= read -r f; do
        sed -i "s#${esc_url}#${rel}#g" "$f"
    done < "$TMPDIR/files.list"
done < "$TMPDIR/urls.list"

echo "Done. Re-run offline-check.sh to verify."
