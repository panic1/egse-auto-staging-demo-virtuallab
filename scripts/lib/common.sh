#!/usr/bin/env bash
# Common helpers for the demo lifecycle scripts in ../.. .
# Source this file from a script:
#   . "$(dirname "$0")/lib/common.sh"
#
# Core demo concept: the demo is OFFLINE-FIRST. Every external asset (Ubuntu
# cloud image, PXE boot files, the .deb bundle) is cached under lab/cache/.
# Each script probes the network: when a stable network is reachable it
# fetches-and-caches; when it is not, it falls back to the cache automatically.
# So the offline scenario is a ready-made backup, not a special mode.

set -euo pipefail

# Repo root and derived paths (this file lives in <repo>/scripts/lib/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_DIR="$REPO_ROOT/lab"
CACHE_DIR="$LAB_DIR/cache"

# Host:port probed to decide whether a stable network exists. A pure-TCP check
# (bash /dev/tcp) is used instead of ping/curl: ICMP is often filtered on lab
# networks, and this needs no curl/wget installed on the host.
ONLINE_PROBE_HOST="${ONLINE_PROBE_HOST:-archive.ubuntu.com}"
ONLINE_PROBE_PORT="${ONLINE_PROBE_PORT:-443}"

# Return 0 (reachable) when a stable network exists, 1 otherwise.
# Bounded by `timeout` so an unreachable host fails fast instead of hanging on
# the kernel's default connect timeout.
is_online() {
  timeout 6 bash -c "exec 3<>/dev/tcp/${ONLINE_PROBE_HOST}/${ONLINE_PROBE_PORT}" 2>/dev/null
}

# Print the detected mode: "online" or "offline".
detect_mode() {
  if is_online; then
    echo online
  else
    echo offline
  fi
}

# Abort with guidance when the cache is missing but needed (offline).
require_cache() {
  if [ ! -d "$CACHE_DIR" ] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]; then
    echo "ERROR: network unavailable and lab/cache/ is empty." >&2
    echo "  Run ./scripts/fetch_dependencies.sh once on a connected machine" >&2
    echo "  so the demo can fall back to offline mode." >&2
    exit 1
  fi
}

# Fetch a URL into the cache unless it is already there. Returns the cached
# path. Fails (with guidance) if offline and the asset is missing.
fetch_or_fallback() {
  local url="$1"
  local out="$CACHE_DIR/$(basename "$url")"

  if [ -f "$out" ]; then
    echo "$out"
    return
  fi

  if is_online; then
    mkdir -p "$CACHE_DIR"
    echo "Downloading $url ..." >&2
    curl -fSL -o "$out" "$url"
    echo "$out"
    return
  fi

  echo "ERROR: '$url' is not cached and the network is unavailable." >&2
  echo "  Run ./scripts/fetch_dependencies.sh on a connected machine." >&2
  exit 1
}