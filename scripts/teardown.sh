#!/usr/bin/env bash
# Tear down the virtual lab: destroy the VMs and the staging network, and clean
# up lab artifacts.
#
# Core demo concept: teardown is the reverse of setup and just as idempotent —
# re-running it is safe. Whether the dependency cache, golden image, and ssh
# keys are also removed is configured in the inventory
# (group_vars/all.yml, teardown_clean, default true), so teardown is
# reproducible with no command-line flags.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

# Names come from the inventory when possible; fallbacks keep teardown working
# even without ansible installed.
STAGING_NAME="staging-server"
STAGING_NET="$(labvar $STAGING_NAME staging_network staging-net)"
PRODUCTION_NET="$(labvar $STAGING_NAME production_network production-net)"
STORAGE_POOL="$(labvar $STAGING_NAME storage_pool default)"
PC_PREFIX="$(labvar $STAGING_NAME egse_pc_name_prefix egse_pc-)"
TEARDOWN_CLEAN="$(labvar $STAGING_NAME teardown_clean true | tr '[:upper:]' '[:lower:]')"

destroy_domain() {
  local name="$1"
  if vsh dominfo "$name" >/dev/null 2>&1; then
    echo "Destroying VM $name ..."
    vsh destroy "$name" 2>/dev/null || true
    vsh undefine --remove-all-storage "$name" 2>/dev/null || true
  fi
}

destroy_network() {
  local net="$1"
  if vsh net-info "$net" >/dev/null 2>&1; then
    echo "Destroying network $net ..."
    vsh net-destroy "$net" 2>/dev/null || true
    vsh net-undefine "$net" 2>/dev/null || true
  fi
}

# All managed domains: the staging server and any EGSE PCs.
destroy_domain "$STAGING_NAME"
for d in $(vsh list --name --all 2>/dev/null | grep -E "^$PC_PREFIX"); do
  destroy_domain "$d"
done

# The demo's own networks (system daemon).
destroy_network "$STAGING_NET"
destroy_network "$PRODUCTION_NET"

# Drop any leftover pool volumes (e.g. from a run that failed before the VM
# was defined). Named volumes: the staging server's disk + seed, and any PC.
for vol in staging-server.qcow2 seed-staging-server.iso; do
  vsh vol-delete --pool "$STORAGE_POOL" "$vol" 2>/dev/null || true
done
for vol in $(vsh vol-list "$STORAGE_POOL" 2>/dev/null | awk '{print $1}' | grep -E "^$PC_PREFIX"); do
  vsh vol-delete --pool "$STORAGE_POOL" "$vol" 2>/dev/null || true
done

echo "Removing lab artifacts ..."
rm -f "$LAB_DIR"/*.qcow2 "$LAB_DIR"/*.iso "$LAB_DIR"/*.xml
rm -rf "$LAB_DIR/seed"

if [ "$TEARDOWN_CLEAN" = true ]; then
  echo "teardown_clean=true: removing dependency cache, golden image, deploy assets, ssh keys, and the offline apt repo ..."
  rm -rf "$LAB_DIR/cache" "$LAB_DIR/keys" "$LAB_DIR/golden.img" "$LAB_DIR/deploy" "$LAB_DIR/apt-repo"
else
  echo "teardown_clean=false: keeping cache, golden image, deploy assets, ssh keys, and the offline apt repo."
fi

echo "Done."