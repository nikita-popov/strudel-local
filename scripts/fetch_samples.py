#!/usr/bin/env python3
"""
Download all Strudel sample manifests + referenced audio files locally.
Supports optional SOCKS5 proxy via --proxy or SAMPLES_PROXY env var.
"""
import json
import os
import sys
import time
import argparse
import urllib.request
import urllib.error
import socket
from pathlib import Path
from urllib.parse import urljoin, urlparse

MANIFESTS = {
    "piano.json": "https://strudel.b-cdn.net/piano.json",
    "vcsl.json": "https://strudel.b-cdn.net/vcsl.json",
    "tidal-drum-machines.json": "https://strudel.b-cdn.net/tidal-drum-machines.json",
    "tidal-drum-machines-alias.json": "https://strudel.b-cdn.net/tidal-drum-machines-alias.json",
    "uzu-drumkit.json": "https://strudel.b-cdn.net/uzu-drumkit.json",
    "uzu-wavetables.json": "https://strudel.b-cdn.net/uzu-wavetables.json",
    "mridangam.json": "https://strudel.b-cdn.net/mridangam.json",
}

RETRIES = 3
TIMEOUT = 20
MANIFEST_TIMEOUT = 30


def setup_proxy(proxy_url: str):
    """Route all socket traffic through a SOCKS5 proxy (e.g. socks5://127.0.0.1:1080)."""
    try:
        import socks
    except ImportError:
        print("ERROR: SOCKS5 proxy requested but 'PySocks' is not installed.")
        print("Install with: pip install PySocks")
        sys.exit(1)

    parsed = urlparse(proxy_url)
    if parsed.scheme not in ("socks5", "socks5h"):
        print(f"ERROR: unsupported proxy scheme '{parsed.scheme}', expected socks5:// or socks5h://")
        sys.exit(1)

    rdns = parsed.scheme == "socks5h"  # resolve DNS through the proxy
    host, port = parsed.hostname, parsed.port or 1080
    username, password = parsed.username, parsed.password

    socks.set_default_proxy(socks.SOCKS5, host, port, rdns=rdns, username=username, password=password)
    socket.socket = socks.socksocket
    print(f"Using SOCKS5 proxy: {host}:{port} (dns_via_proxy={rdns})")


def fetch(url: str, timeout: int = TIMEOUT) -> bytes:
    last_err = None
    for attempt in range(1, RETRIES + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "strudel-local-mirror/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.URLError, socket.timeout, OSError) as e:
            last_err = e
            print(f"  retry {attempt}/{RETRIES} for {url}: {e}")
            time.sleep(2 * attempt)
    raise RuntimeError(f"failed to fetch {url}: {last_err}")


def collect_urls(node, base_url, acc):
    if isinstance(node, dict):
        local_base = urljoin(base_url, node["_base"]) if "_base" in node and isinstance(node["_base"], str) else base_url
        for k, v in node.items():
            if k == "_base":
                continue
            collect_urls(v, local_base, acc)
    elif isinstance(node, list):
        for item in node:
            collect_urls(item, base_url, acc)
    elif isinstance(node, str):
        if node.startswith("http://") or node.startswith("https://"):
            acc.append(node)
        else:
            acc.append(urljoin(base_url + ("/" if not base_url.endswith("/") else ""), node))


def rewrite_node(node, base_url, manifest_dir):
    if isinstance(node, dict):
        new_base = urljoin(base_url, node["_base"]) if "_base" in node and isinstance(node["_base"], str) else base_url
        out = {}
        for k, v in node.items():
            if k == "_base":
                out["_base"] = "./"
                continue
            out[k] = rewrite_node(v, new_base, manifest_dir)
        return out
    elif isinstance(node, list):
        return [rewrite_node(item, base_url, manifest_dir) for item in node]
    elif isinstance(node, str):
        abs_url = node if node.startswith("http") else urljoin(base_url + ("/" if not base_url.endswith("/") else ""), node)
        parsed = urlparse(abs_url)
        rel_path = parsed.path.lstrip("/")
        return rel_path.split("/", 1)[-1] if rel_path.startswith(manifest_dir.name + "/") else rel_path
    return node


def process_manifest(filename, manifest_url, out_dir: Path):
    print(f"\n== {filename} ==")
    manifest_dir = out_dir / filename.replace(".json", "")
    manifest_dir.mkdir(parents=True, exist_ok=True)

    try:
        raw = fetch(manifest_url, timeout=MANIFEST_TIMEOUT)
    except RuntimeError as e:
        print(f"  SKIPPED manifest: {e}")
        return False

    data = json.loads(raw)
    base_url = manifest_url.rsplit("/", 1)[0] + "/"

    urls = []
    collect_urls(data, base_url, urls)
    urls = sorted(set(urls))
    print(f"  {len(urls)} audio files referenced")

    failed = 0
    for i, url in enumerate(urls, 1):
        parsed = urlparse(url)
        rel_path = parsed.path.lstrip("/")
        rel_path = rel_path.split("/", 1)[-1] if rel_path.startswith(manifest_dir.name + "/") else rel_path
        dest = manifest_dir / rel_path
        if dest.exists() and dest.stat().st_size > 0:
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            content = fetch(url)
            dest.write_bytes(content)
            if i % 20 == 0 or i == len(urls):
                print(f"  [{i}/{len(urls)}] downloaded")
        except RuntimeError as e:
            failed += 1
            print(f"  WARNING: skipped {url}: {e}")

    rewritten = rewrite_node(data, base_url, manifest_dir)
    (out_dir / filename).write_text(json.dumps(rewritten, indent=2))
    print(f"  manifest rewritten -> {out_dir / filename} ({failed} file(s) failed)")
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir", nargs="?", default="samples")
    parser.add_argument("--proxy", default=os.environ.get("SAMPLES_PROXY"),
                         help="SOCKS5 proxy URL, e.g. socks5://127.0.0.1:1080 or socks5h://user:pass@host:1080")
    args = parser.parse_args()

    if args.proxy:
        setup_proxy(args.proxy)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = {}
    for filename, url in MANIFESTS.items():
        results[filename] = process_manifest(filename, url, out_dir)

    print("\n=== Summary ===")
    for filename, ok in results.items():
        print(f"  {filename}: {'OK' if ok else 'SKIPPED'}")

    if not any(results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
