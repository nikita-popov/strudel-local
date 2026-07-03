FROM node:24-trixie AS build
#FROM node:24-bookworm AS build

WORKDIR /src

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates python3-yaml \
 && rm -rf /var/lib/apt/lists/*

ARG STRUDEL_REPO=https://codeberg.org/uzu/strudel
ARG STRUDEL_REF=

# Clone: use explicit ref only if provided, otherwise take upstream default branch
RUN if [ -n "$STRUDEL_REF" ]; then \
      git clone --depth 1 --branch "$STRUDEL_REF" "$STRUDEL_REPO" .; \
    else \
      git clone --depth 1 "$STRUDEL_REPO" .; \
    fi

# Use the pnpm version pinned by the project itself (packageManager field)
RUN corepack enable
#RUN corepack install
RUN corepack prepare pnpm@9 --activate

# Redirect default sample map to local nginx samples endpoint (see patches/)
COPY patches/ /patches/
RUN git apply /patches/0001-local-samples.patch || echo "WARNING: sample patch did not apply cleanly, verify manually"

# Merge onlyBuiltDependencies into pnpm-workspace.yaml (pnpm v10+ ignores package.json for this)
RUN python3 - <<'PY'
import yaml
from pathlib import Path

p = Path('pnpm-workspace.yaml')
data = yaml.safe_load(p.read_text()) if p.exists() else {}
data = data or {}

deps = set(data.get('onlyBuiltDependencies', []))
deps.update([
    '@serialport/bindings-cpp',
    'esbuild',
    'nx',
    'sharp',
    'tree-sitter',
    'tree-sitter-haskell',
])
data['onlyBuiltDependencies'] = sorted(deps)

p.write_text(yaml.safe_dump(data, sort_keys=False))
PY

RUN echo "=== pnpm-workspace.yaml after patch ===" && cat pnpm-workspace.yaml

RUN pnpm install

# ── Fallback if the whitelist above is not enough ────────────────────────────
# If `pnpm install` still fails with ERR_PNPM_IGNORED_BUILDS, uncomment below
# and remove the block above, then rebuild with --no-cache:
#
# RUN printf '\ndangerouslyAllowAllBuilds: true\n' >> pnpm-workspace.yaml
# RUN pnpm install

RUN pnpm build

RUN grep -rl "strudel.b-cdn.net" website/dist/_astro/*.js 2>/dev/null | \
    xargs -r sed -i 's|https://strudel\.b-cdn\.net|/samples|g'

RUN echo "=== remaining b-cdn.net refs (should be empty) ===" \
 && grep -rl "b-cdn.net" website/dist/_astro/*.js 2>/dev/null || true

RUN test -d website/dist || (echo "ERROR: website/dist not found after build" && exit 1)

# ── Export stage (bare artifact, no runtime) ─────────────────────────────────
FROM scratch AS export
COPY --from=build /src/website/dist/ /
