#!/bin/sh
# offline-check.sh <dist-dir>
# Exit 1 if any external URL is found in the built assets.
set -eu

DIST="${1:-./dist}"
PATTERN='https?://|//cdn\.|fonts\.googleapis|fonts\.gstatic|unpkg\.com|jsdelivr\.net|raw\.githubusercontent\.com|freesound\.org|shabda\.net|bunny\.net|\.b-cdn\.net'

echo "Checking $DIST for external references..."
FOUND=$(grep -RInE "$PATTERN"     --include="*.html"     --include="*.js"     --include="*.mjs"     --include="*.css"     --include="*.json"     "$DIST" 2>/dev/null || true)

if [ -n "$FOUND" ]; then
    echo "FAIL: external references found:"
    echo "$FOUND"
    exit 1
fi

echo "OK: no external references found."
