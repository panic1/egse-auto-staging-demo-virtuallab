#!/usr/bin/env bash
# Fetch the lab's offline dependencies: the bundled apt repo both the EGSE PC
# and the staging server install from when the lab runs without a network.
#
# Core demo concept: software normally comes from the Ubuntu archive (the lab
# is ONLINE by default). To run OFFLINE, this script bundles the exact package
# sets — the PC's EGSE stack (inventory/group_vars/egse_pcs.yml,
# egse_pc_packages) and the staging server's own tools
# (inventory/group_vars/staging.yml, staging_packages) — plus all their
# dependencies into a small flat apt repo at lab/apt-repo/.
#
#   - The PC installs from it over HTTP: the staging server serves the repo at
#     apt_repo_url (see ROADMAP Task 7).
#   - The staging server installs from it locally (file:.../lab/apt-repo), so
#     setup.sh can recreate and provision the staging server with no network
#     (see ROADMAP Task 12).
#
# Scope: only the lab has an offline mode. This script does not cache the cloud
# image, deploy kernel, or PXE files — those are fetched at online setup.
# Golden image, deploy tool, and cloud image are kept across teardown with
# teardown_clean: false.
#
# Idempotent: re-running skips work whose output already exists. Delete
# lab/apt-repo to rebuild (e.g. after changing egse_pc_packages or
# staging_packages).
#
# setup.sh calls this automatically when online, so one online run primes the
# offline backup.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

APT_REPO_DIR="$(labvar staging-server apt_repo_dir lab/apt-repo)"
APT_REPO="$REPO_ROOT/$APT_REPO_DIR"
APT_REPO_URL="$(labvar staging-server apt_repo_url http://10.10.122.2/apt)"

main() {
  require_commands apt-get apt-cache dpkg-scanpackages gzip sha256sum

  if ! is_online; then
    echo "ERROR: fetch_dependencies.sh needs the network to build the apt repo." >&2
    echo "  Run it on a connected machine once; then the demo can run offline." >&2
    exit 1
  fi

  if [ -f "$APT_REPO/Packages.gz" ]; then
    echo "Bundled apt repo already built: $APT_REPO"
    echo "  (served to the PC at $APT_REPO_URL in offline mode)"
    echo "  Delete $APT_REPO to rebuild (e.g. after changing egse_pc_packages)."
    return 0
  fi

  # apt-cache/apt-get need the host's package lists to resolve and download.
  echo "Refreshing host package lists (needed to resolve dependencies) ..."
  if ! sudo apt-get update >/dev/null 2>&1; then
    echo "WARNING: apt-get update reported errors; continuing with existing lists." >&2
  fi

  local pkgs=()
  local pkg
  local pkg_host
  # egse_pc_packages is a group-level var (same set for every PC, see
  # inventory/group_vars/egse_pcs.yml), so read it from any PC in the inventory
  # rather than hardcoding a specific host.
  pkg_host="$(list_pcs | head -1)"
  if [ -z "$pkg_host" ]; then
    echo "ERROR: no EGSE PCs found in the inventory." >&2
    exit 1
  fi
  while read -r pkg; do
    [ -n "$pkg" ] && pkgs+=("$pkg")
  done < <(labvar_list "$pkg_host" egse_pc_packages)
  if [ "${#pkgs[@]}" -eq 0 ]; then
    echo "ERROR: no egse_pc_packages found in the inventory." >&2
    exit 1
  fi

  # The staging server's own packages (dnsmasq, pxelinux, ansible, rsync) are
  # bundled into the same repo, so setup.sh can provision/recreate the staging
  # server with no network at the meeting (inventory/group_vars/staging.yml).
  # Read them from the staging-server host.
  local staging_pkgs
  staging_pkgs="$(labvar_list staging-server staging_packages | grep -v '^$' | tr '\n' ' ')"
  if [ -z "$staging_pkgs" ]; then
    echo "WARNING: no staging_packages found in the inventory;" >&2
    echo "  the staging server will not be installable offline." >&2
  else
    for pkg in $staging_pkgs; do
      pkgs+=("$pkg")
    done
  fi

  echo "Bundling the lab's offline package set:"
  echo "  EGSE PC stack     : $(labvar_list "$pkg_host" egse_pc_packages | grep -v '^$' | tr '\n' ' ')"
  echo "  staging server    : ${staging_pkgs:-<none>}"

  mkdir -p "$APT_REPO"

  echo "Resolving the dependency closure ..."
  local deps
  deps="$(resolve_deps "${pkgs[@]}")"

  echo "Downloading packages into $APT_REPO ..."
  (
    cd "$APT_REPO" || exit 1
    # apt-get download may fail on virtual packages (e.g. alternatives) —
    # warn and continue for those.
    local name
    for name in ${pkgs[*]} $deps; do
      if ! apt-get download "$name" >/dev/null 2>&1; then
        echo "NOTE: skipped '$name' (virtual or not downloadable)." >&2
      fi
    done
  )

  if ! ls "$APT_REPO"/*.deb >/dev/null 2>&1; then
    echo "ERROR: no packages were downloaded into $APT_REPO." >&2
    exit 1
  fi

  echo "Building the flat repo index and checksum manifest ..."
  # Flat repos (deb ... ./) need the uncompressed Packages index (apt fetches
  # ./Packages); Packages.gz is a convenience for smaller fetches.
  ( cd "$APT_REPO" && dpkg-scanpackages . /dev/null | tee Packages | gzip -9 > Packages.gz )
  ( cd "$APT_REPO" && sha256sum *.deb > SHA256SUMS )

  echo
  echo "Done. Bundled apt repo: $APT_REPO"
  echo "  package count : $(ls "$APT_REPO"/*.deb | wc -l)"
  echo "  served to the PC at $APT_REPO_URL (offline demo)"
}

# Resolve the full dependency closure of the given packages, deduplicated,
# from the host's apt lists (apt-cache). No Recommends/Suggests — keep the
# bundle small and deterministic.
resolve_deps() {
  apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
    --no-breaks --no-replaces --no-enhances "$@" \
    | grep -E '^[[:space:]]+(Depends|PreDepends):' \
    | sed -E 's/^[[:space:]]+[A-Za-z]+: //; s/[|].*$//; s/[:<>=].*$//; s/[[:space:]]+$//' \
    | grep -v '^$' \
    | sort -u
}

main "$@"