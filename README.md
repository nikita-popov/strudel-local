# strudel-local

Build [Strudel](https://strudel.cc) from source in Docker and serve it fully offline behind a local nginx — no external CDN, no external fonts, no external sample hosts.

## Design

```
Dockerfile (multi-stage)
    └── git clone codeberg.org/uzu/strudel   (pinned to STRUDEL_REF)
    └── apply patches/0001-local-samples.patch
    └── pnpm install && pnpm build
    └── website/dist → ./dist (exported via docker cp)

External nginx  ← primary target
    /               → ./dist/
    /samples/       → ./samples/  (local audio packs)
    sw.js           → no-cache

Optional internal nginx  (docker compose --profile dev)
    same volumes, for local smoke-testing only
```

## Requirements

| Tool | Version |
|------|---------|
| Docker Engine | 24+ |
| Docker Compose | v2 (plugin) |
| GNU make | any |
| rsync | any |
| External nginx | 1.24+ |

## Quick Start

```bash
# 1. Clone
git clone https://github.com/nikita-popov/strudel-local
cd strudel-local

# 2. Download samples (optional but needed for full offline)
git clone --depth 1 https://github.com/tidalcycles/Dirt-Samples samples/dirt-samples

# 3. Build and export dist/
make all              # build + export + offline-check

# 4. Deploy to external nginx
sudo make install           # rsync dist/ → /srv/http/strudel/
sudo make install-samples   # rsync samples/ → /srv/http/strudel-samples/

# 5. Install nginx config
sudo cp nginx/strudel.conf /etc/nginx/sites-available/strudel.conf
sudo ln -sf /etc/nginx/sites-available/strudel.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo nginx -s reload
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `build` | Build Docker image |
| `export` | Extract `website/dist` into `./dist` |
| `all` | `build + export + offline-check` |
| `offline-check` | Fail if any external URL found in dist |
| `mirror-assets` | Download + rewrite external URLs (fallback) |
| `install` | rsync `dist/` → `NGINX_ROOT` |
| `install-samples` | rsync `samples/` → `SAMPLES_ROOT` |
| `update` | Rebuild from latest `STRUDEL_REF` |
| `dev-up` | Start optional internal nginx (profile=dev) |
| `dev-down` | Stop internal nginx |
| `dev-logs` | Follow internal nginx logs |
| `shell` | Enter build container for debugging |
| `clean` | Remove `./dist` |

## Configuration

Copy `.env.example` to `.env` and adjust:

```bash
STRUDEL_REPO=https://codeberg.org/uzu/strudel
STRUDEL_REF=master
NGINX_PORT=127.0.0.1:8080
```

Or pass variables to make directly:

```bash
make build STRUDEL_REF=v1.2.0
```

## Offline Check

`scripts/offline-check.sh` greps all built HTML/JS/CSS/JSON for known external
patterns (githubusercontent, freesound, bunny CDN, unpkg, jsdelivr, shabda, …).
Exit code 1 if any match is found.

```bash
make offline-check
```

The `make all` target always runs this check after export.

## Applying the Sample Patch

`patches/0001-local-samples.patch` rewrites the default sample base URL in
`website/src/repl/prebake.mjs` from the external CDN to `/samples/`.

The target file and URL string change between Strudel releases.
If the patch does not apply cleanly, the Dockerfile prints a warning — fix it:

```bash
# Find the relevant line
grep -rn "githubusercontent\|bunny\|strudel.json" /path/to/strudel/website/src/repl/

# Update the patch to match the current file and URL
```

A sed fallback is documented in the patch file as a comment.

## Adding Sample Packs

```bash
# Any folder structure works; each top-level subdir becomes a sound bank
mkdir -p samples/my-pack/kick samples/my-pack/snare
cp *.wav samples/my-pack/kick/

# Generate strudel.json for the pack
cd samples/my-pack && npx @strudel/sampler --json > strudel.json

# Install
make install-samples

# Use in Strudel code
# samples('/samples/my-pack/strudel.json')
```

## POLYSERV Integration

If Strudel sits behind a reverse proxy in your POLYSERV setup, the nginx block
in `nginx/strudel.conf` is a drop-in server block.  Adjust `server_name` and
`root`.  `nginx/headers.conf` provides the Content-Security-Policy that blocks
all external fetches — include it in your main nginx config with:

```nginx
include /etc/nginx/conf.d/headers.conf;
```

## Updating Strudel

```bash
make update
sudo make install
sudo nginx -s reload
```

## Repository Structure

```
strudel-local/
├── Dockerfile               Multi-stage: build → export
├── docker-compose.yml       builder (profile=build) + nginx (profile=dev)
├── Makefile                 All workflow targets
├── .env.example             Environment template
├── .gitignore
├── nginx/
│   ├── strudel.conf         External nginx server block
│   └── headers.conf         Security + CSP headers
├── patches/
│   └── 0001-local-samples.patch  Rewrites sample URL to /samples/
├── samples/
│   └── README.md            How to add sample packs
└── README.md
```

## License

MIT
