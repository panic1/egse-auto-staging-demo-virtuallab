#!/usr/bin/env bash
# Bring up the virtual lab's networks and the staging server VM.
#
# Core demo concept: the staging server is the machine that preps industrial
# PCs. Here it is created as a VM with two NICs:
#   - eth0 on the NAT "production" network (management / Ansible)
#   - eth1 on the isolated staging network, where it will later PXE-boot PCs
# The staging network is deliberately L2-only: the host has no address on it,
# so the PCs are only ever reachable through the staging server.
#
# Everything runs in the system daemon (qemu:///system, see libvirt_uri in the
# inventory) because the demo needs bridge networks, which the session daemon
# cannot create. VM disks and seed ISOs are created as volumes in the libvirt
# 'default' storage pool (see storage_pool), so the libvirt-qemu user can
# access them without touching this repo's permissions.
#
# All VM sizing, addresses, MACs, and network names come from the Ansible
# inventory (see scripts/lib/common.sh labvar) — the single source of truth.
# Everything here is idempotent: re-running setup from a clean state works.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

STAGING_NAME="staging-server"
STAGING_NET="$(labvar $STAGING_NAME staging_network)"
PRODUCTION_NET="$(labvar $STAGING_NAME production_network)"
STAGING_NET_XML="$LAB_DIR/$STAGING_NET.xml"

STAGING_HOST="$(labvar $STAGING_NAME mgmt_ip)"
STAGING_IP="$(labvar $STAGING_NAME staging_ip)"
MGMT_MAC="$(labvar $STAGING_NAME mgmt_mac)"
STAGING_MAC="$(labvar $STAGING_NAME staging_mac)"
PROD_GATEWAY="$(labvar $STAGING_NAME production_gateway)"
PROD_DNS="$(labvar $STAGING_NAME production_dns)"
PROD_BRIDGE="$(labvar $STAGING_NAME production_network_bridge virbr-prod)"

STAGING_MEM_MB="$(labvar $STAGING_NAME staging_vm_memory_mb)"
STAGING_VCPUS="$(labvar $STAGING_NAME staging_vm_vcpus)"
STAGING_DISK_GB="$(labvar $STAGING_NAME staging_vm_disk_gb)"
OS_VARIANT="$(labvar $STAGING_NAME os_variant)"
NIC_MODEL="$(labvar $STAGING_NAME nic_model)"

# VM-attached files live in the libvirt storage pool (not under this repo).
STORAGE_POOL="$(labvar $STAGING_NAME storage_pool default)"
STAGING_DISK_VOL="staging-server.qcow2"
SEED_ISO_VOL="seed-staging-server.iso"

# Intermediate seed files live under repo lab/ and are uploaded into the pool.
SEED_ISO="$LAB_DIR/$SEED_ISO_VOL"
SEED_DIR="$LAB_DIR/seed"

CLOUD_IMG_URL="$(labvar $STAGING_NAME cloud_image_url)"
CLOUD_IMG_CACHE="$CACHE_DIR/$(basename "$CLOUD_IMG_URL")"

# Whether to open a show-and-tell ssh terminal into the staging server once it
# is up. Configured in the inventory (group_vars/all.yml,
# open_terminal_on_setup) rather than as a command-line flag. Lowercased
# because ansible-inventory serializes YAML booleans as 'True'/'False'.
OPEN_TERMINAL="$(labvar $STAGING_NAME open_terminal_on_setup false | tr '[:upper:]' '[:lower:]')"

main() {
  require_commands virsh virt-install qemu-img cloud-localds ssh-keygen curl \
    ansible-inventory python3

  ensure_ssh_key
  ensure_production_network
  ensure_staging_network
  ensure_cloud_image
  create_staging_server
  start_staging_server
  wait_for_ssh "$STAGING_HOST" ops "$LAB_DIR/keys/egse-demo"

  if [ "$OPEN_TERMINAL" = true ]; then
    open_ssh_terminal "staging server" ops "$STAGING_HOST" "$LAB_DIR/keys/egse-demo"
  fi
}

# The production network is defined here in the system daemon. If it does not
# exist it is created as a NAT network (see config: production_subnet). Uses
# `vsh net-info` (not `net-list --active`) so it works with older libvirt.
ensure_production_network() {
  local info=""
  if ! info="$(vsh net-info "$PRODUCTION_NET" 2>/dev/null)"; then
    define_production_network
    return
  fi
  if printf '%s\n' "$info" | grep -Eq '^Active:[[:space:]]+yes$'; then
    return
  fi
  # Defined but not active. If starting fails, drop any leftover definition
  # (transient or persistent) and define it cleanly.
  if ! vsh net-start "$PRODUCTION_NET" 2>/dev/null; then
    echo "WARNING: starting '$PRODUCTION_NET' failed — redefining it." >&2
    vsh net-destroy "$PRODUCTION_NET" 2>/dev/null || true
    vsh net-undefine "$PRODUCTION_NET" 2>/dev/null || true
    define_production_network
  fi
}

define_production_network() {
  echo "Defining libvirt '$PRODUCTION_NET' network (NAT, no DHCP) ..."
  local xml="$LAB_DIR/$PRODUCTION_NET.xml"
  mkdir -p "$LAB_DIR"
  cat > "$xml" <<EOF
<network>
  <name>$PRODUCTION_NET</name>
  <forward mode="nat"/>
  <bridge name="$PROD_BRIDGE"/>
  <ip address="$PROD_GATEWAY" netmask="255.255.255.0"/>
</network>
EOF
  vsh net-define "$xml"
  vsh net-autostart "$PRODUCTION_NET"
  vsh net-start "$PRODUCTION_NET"
}

ensure_staging_network() {
  if vsh net-info "$STAGING_NET" >/dev/null 2>&1; then
    echo "Network $STAGING_NET already exists."
    return
  fi
  echo "Defining isolated network $STAGING_NET ..."
  mkdir -p "$LAB_DIR"
  cat > "$STAGING_NET_XML" <<EOF
<network>
  <name>$STAGING_NET</name>
  <bridge name="virbr-staging"/>
  <forward mode="none"/>
</network>
EOF
  vsh net-define "$STAGING_NET_XML"
  vsh net-start "$STAGING_NET"
}

# The storage pool holds all VM-attached files (disks, seed ISOs) so the
# libvirt-qemu user can access them without touching this repo's permissions.
ensure_storage_pool() {
  if vsh pool-info "$STORAGE_POOL" >/dev/null 2>&1; then
    return
  fi
  echo "Storage pool '$STORAGE_POOL' missing — defining the standard one ..."
  vsh pool-define-as "$STORAGE_POOL" dir --target /var/lib/libvirt/images
  vsh pool-autostart "$STORAGE_POOL"
  vsh pool-start "$STORAGE_POOL"
}

# Delete + recreate a pool volume (safe across failed/partial runs).
pool_volume_reset() {
  local vol="$1"
  local cap="$2"
  local fmt="$3"
  vsh vol-delete --pool "$STORAGE_POOL" "$vol" 2>/dev/null || true
  vsh vol-create-as "$STORAGE_POOL" "$vol" --capacity "$cap" --format "$fmt"
}

pool_volume_upload() {
  local vol="$1"
  local file="$2"
  vsh vol-upload --pool "$STORAGE_POOL" "$vol" "$file"
}

pool_volume_resize() {
  local vol="$1"
  local size="$2"
  vsh vol-resize --pool "$STORAGE_POOL" "$vol" "$size"
}

ensure_cloud_image() {
  echo "Ensuring the Ubuntu cloud image is available ..."
  fetch_or_fallback "$CLOUD_IMG_URL" >/dev/null
}

create_staging_server() {
  if vsh dominfo "$STAGING_NAME" >/dev/null 2>&1; then
    echo "VM $STAGING_NAME already exists."
    return
  fi

  ensure_storage_pool

  # 1. Disk: a pool volume seeded with the cloud image, then grown. cloud-init
  #    'growpart' expands the root partition on first boot.
  echo "Creating the staging server disk in pool '$STORAGE_POOL' ..."
  local cloud_vsize
  cloud_vsize="$(qemu-img info --output json "$CLOUD_IMG_CACHE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')"
  pool_volume_reset "$STAGING_DISK_VOL" "$cloud_vsize" qcow2
  pool_volume_upload "$STAGING_DISK_VOL" "$CLOUD_IMG_CACHE"
  pool_volume_resize "$STAGING_DISK_VOL" "${STAGING_DISK_GB}G"

  # 2. Seed ISO: built locally (repo lab/), then uploaded into the pool so the
  #    VM's cdrom is readable by libvirt-qemu.
  echo "Building the cloud-init seed (user, ssh key, network config) ..."
  mkdir -p "$SEED_DIR"
  cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: $STAGING_NAME
users:
  - name: ops
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$LAB_DIR/keys/egse-demo.pub")
ssh_pwauth: false
disable_root: true
EOF
  cat > "$SEED_DIR/meta-data" <<EOF
instance-id: $STAGING_NAME
local-hostname: $STAGING_NAME
EOF
  cat > "$SEED_DIR/network-config" <<EOF
version: 2
ethernets:
  mgmt:
    match:
      macaddress: "$MGMT_MAC"
    addresses: ["$STAGING_HOST/24"]
    routes:
      - to: default
        via: $PROD_GATEWAY
    nameservers:
      addresses: [$PROD_DNS]
  staging:
    match:
      macaddress: "$STAGING_MAC"
    addresses: ["$STAGING_IP/24"]
EOF
  cloud-localds --network-config "$SEED_DIR/network-config" \
    "$SEED_ISO" "$SEED_DIR/user-data" "$SEED_DIR/meta-data"
  pool_volume_reset "$SEED_ISO_VOL" "$(stat -c %s "$SEED_ISO")" raw
  pool_volume_upload "$SEED_ISO_VOL" "$SEED_ISO"

  echo "Creating the staging server VM ..."
  virt-install --connect "$LIBVIRT_URI" \
    --name "$STAGING_NAME" \
    --memory "$STAGING_MEM_MB" \
    --vcpus "$STAGING_VCPUS" \
    --os-variant "$OS_VARIANT" \
    --import \
    --noautoconsole \
    --disk vol="$STORAGE_POOL/$STAGING_DISK_VOL",format=qcow2 \
    --disk vol="$STORAGE_POOL/$SEED_ISO_VOL",device=cdrom,format=raw \
    --network network="$PRODUCTION_NET",model="$NIC_MODEL",mac="$MGMT_MAC" \
    --network network="$STAGING_NET",model="$NIC_MODEL",mac="$STAGING_MAC"
}

start_staging_server() {
  if [ "$(vsh domstate "$STAGING_NAME")" != "running" ]; then
    echo "Starting $STAGING_NAME ..."
    vsh start "$STAGING_NAME"
  fi
}

main "$@"