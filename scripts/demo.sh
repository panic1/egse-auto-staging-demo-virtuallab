#!/usr/bin/env bash
# Run the full EGSE auto-staging demo: stage a bare PC, install the golden
# image over the network, configure it on the staging network, hand it over
# to the production network, and verify its end state.
#
# Core demo concept: an industrial PC goes from a bare machine to a
# configured, verified machine with no manual steps, through four stages:
#
#   1. Stage      - a bare PC VM is created (empty disk, PXE boot on the
#                   isolated staging network) - a freshly delivered PC.
#   2. Install    - the PC PXE-boots, the staging server's dnsmasq hands it
#                   the deploy kernel + initramfs, which downloads the golden
#                   image over HTTP and writes it to disk. The PC then powers
#                   off; the demo boots it normally.
#   3. Configure  - Ansible (from the staging server) applies the factory
#                   config on the staging network, then the PC is re-cabled
#                   ("shipped") to the production network and configured with
#                   its software and updates.
#   4. Verify     - the end state is asserted (hostname, static address,
#                   packages, updates).
#
# Config-over-flags: pauses and show-and-tell terminals are driven by the
# inventory (group_vars/all.yml: demo_pause, open_terminal_on_demo), never by
# command-line flags, so runs are reproducible.
#
# Prerequisite: ./scripts/setup.sh must have been run (staging server up and
# serving the golden image).

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_HOST="$(labvar staging-server mgmt_ip)"
SSH_KEY="$LAB_DIR/keys/egse-demo"
STORAGE_POOL="$(labvar staging-server storage_pool default)"
STAGING_NET="$(labvar staging-server staging_network)"
PRODUCTION_NET="$(labvar staging-server production_network)"
PC_MEM="$(labvar staging-server egse_pc_vm_memory_mb)"
PC_VCPUS="$(labvar staging-server egse_pc_vm_vcpus)"
PC_DISK_GB="$(labvar staging-server egse_pc_vm_disk_gb)"
OS_VARIANT="$(labvar staging-server os_variant)"
PC_NIC_MODEL="$(labvar staging-server egse_pc_nic_model e1000)"
PC_DISK_BUS="$(labvar staging-server egse_pc_disk_bus ide)"
PC_MACHINE="$(labvar staging-server egse_pc_machine_type pc)"
BOOT_ORDER="$(labvar staging-server egse_pc_boot_order network,hd)"
OPEN_TERMINAL="$(labvar staging-server open_terminal_on_demo false | tr '[:upper:]' '[:lower:]')"
APT_REPO_URL="$(labvar staging-server apt_repo_url http://10.10.122.2/apt)"

# Boot order after the network install: disk first, network as fallback, so a
# reboot never re-triggers the PXE installer.
NORMAL_BOOT="hd,network"

# Demo mode (auto-detected, no flag — see lib/common.sh). Online: the PC's
# production phase uses the Ubuntu archive. Offline: it uses the bundled apt
# repo served by the staging server (apt_repo_url).
MODE="$(detect_mode)"

ssh_opts() {
  echo "-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
}

main() {
  require_commands virsh virt-install virt-xml ansible-inventory python3 ssh curl

  echo "Mode: $MODE"
  if [ "$MODE" = offline ]; then
    echo "  Offline: the PC's software will come from the bundled apt repo ($APT_REPO_URL)."
  fi

  preflight

  local pcs
  pcs="$(list_pcs)"
  if [ -z "$pcs" ]; then
    echo "ERROR: no EGSE PCs found in the inventory." >&2
    exit 1
  fi

  echo
  echo "EGSE auto-staging demo — machines to stage: $pcs"
  demo_pause "start"

  local pc
  for pc in $pcs; do
    stage_one "$pc"
  done

  echo
  echo "Demo complete: all EGSE PCs staged, installed, configured, and verified."
}

# Verify the lab is up (setup.sh ran) before touching any PC.
preflight() {
  echo "Checking the lab is up (staging server + golden image) ..."
  wait_for_ssh "$STAGING_HOST" ops "$SSH_KEY" 10
  if ! curl -sfI "http://$STAGING_HOST/golden.img" >/dev/null; then
    echo "ERROR: the staging server is not serving golden.img." >&2
    echo "  Run ./scripts/setup.sh first." >&2
    exit 1
  fi
  if [ "$MODE" = offline ] && ! curl -sf "http://$STAGING_HOST/apt/Packages.gz" >/dev/null; then
    echo "ERROR: offline demo needs the bundled apt repo served by the staging server." >&2
    echo "  Run ./scripts/setup.sh online once to build and sync it." >&2
    exit 1
  fi
}

# The full four-stage flow for one PC.
stage_one() {
  local pc="$1"
  local mac staging_ip production_ip hostname
  mac="$(labvar "$pc" mac)"
  staging_ip="$(labvar "$pc" staging_ip)"
  production_ip="$(labvar "$pc" production_ip)"
  hostname="$(labvar "$pc" hostname "$pc")"

  step "1/4 STAGE — creating the bare PC VM '$pc' (empty disk, PXE boot on the staging network)"
  echo "  A freshly delivered industrial PC: no OS, booting from the network."
  reset_pc_vm "$pc" "$mac"
  demo_pause "stage"

  step "2/4 INSTALL — '$pc' PXE-boots and installs the golden image"
  echo "  dnsmasq hands it the deploy kernel+initramfs; the golden image is"
  echo "  downloaded over HTTP and written to the disk. Watch live with:"
  echo "    virsh console $pc"
  wait_for_deploy "$pc"

  step "2/4 INSTALL — golden image on disk; booting '$pc' normally"
  virt-xml --connect "$LIBVIRT_URI" "$pc" --edit --boot "$NORMAL_BOOT" >/dev/null
  vsh start "$pc"
  wait_for_ssh "$staging_ip" ops "$SSH_KEY" 60 "ops@$STAGING_HOST"
  if [ "$OPEN_TERMINAL" = true ]; then
    open_ssh_terminal "$pc (staging)" ops "$staging_ip" "$SSH_KEY" "ops@$STAGING_HOST"
  fi
  demo_pause "install"

  step "3/4 CONFIGURE — factory configuration on the staging network"
  echo "  Ansible (from the staging server) sets the hostname, regenerates the"
  echo "  ssh keys, and writes the production netplan for the handover."
  run_pc_playbook egse_pc-staging.yml
  demo_pause "factory configuration"

  step "3/4 HANDOVER — re-cabling '$pc' from the staging to the production network"
  echo "  This simulates the PC shipping to its production location: the same"
  echo "  single network port is moved to the production network."
  shutdown_vm "$pc"
  recable_pc "$pc" "$mac"
  vsh start "$pc"
  wait_for_ssh "$production_ip" ops "$SSH_KEY" 60
  if [ "$OPEN_TERMINAL" = true ]; then
    open_ssh_terminal "$pc (production)" ops "$production_ip" "$SSH_KEY"
  fi
  demo_pause "handover"

  step "4/4 CONFIGURE + VERIFY — production software, updates, and end-state check"
  echo "  On the production network the PC finally gets its EGSE software stack"
  echo "  and OS updates; the playbook ends by asserting the end state."
  run_pc_playbook egse_pc-production.yml
  demo_pause "verification"

  step "Verified: '$pc' is staged, installed, configured, and verified."
  echo "  Hostname: $hostname"
  echo "  Production IP: $production_ip"
}

# Recreate the bare PC VM: fresh raw disk, one e1000 NIC on the staging
# network, PXE-first boot order. virt-install auto-starts it.
reset_pc_vm() {
  local pc="$1" mac="$2"
  if vsh dominfo "$pc" >/dev/null 2>&1; then
    echo "Recreating '$pc' (previous demo run) ..."
    vsh destroy "$pc" 2>/dev/null || true
    vsh undefine --remove-all-storage "$pc"
  fi
  vsh vol-delete --pool "$STORAGE_POOL" "$pc.qcow2" 2>/dev/null || true
  # Raw volume: the golden image (also raw) is dd'd straight onto it.
  vsh vol-create-as "$STORAGE_POOL" "$pc.qcow2" --capacity "${PC_DISK_GB}G" --format raw
  virt-install --connect "$LIBVIRT_URI" \
    --name "$pc" \
    --memory "$PC_MEM" \
    --vcpus "$PC_VCPUS" \
    --os-variant "$OS_VARIANT" \
    --machine "$PC_MACHINE" \
    --import \
    --noautoconsole \
    --disk vol="$STORAGE_POOL/$pc.qcow2",format=raw,bus="$PC_DISK_BUS" \
    --network network="$STAGING_NET",model="$PC_NIC_MODEL",mac="$mac" \
    --boot "$BOOT_ORDER"
}

# Wait for the deploy tool to finish: it writes the golden image and powers
# the machine off, which shows up as the libvirt domain state "shut off".
wait_for_deploy() {
  local pc="$1"
  local tries=120
  echo "  Waiting for the install to finish (image download + disk write) ..."
  for _ in $(seq 1 "$tries"); do
    local st
    st="$(vsh domstate "$pc" 2>/dev/null || echo unknown)"
    if [ "$st" = "shut off" ]; then
      echo "  Install finished: $pc powered off after writing the golden image."
      return 0
    fi
    sleep 5
  done
  echo "ERROR: $pc did not finish the network install in time." >&2
  echo "  Watch it live: virsh console $pc" >&2
  return 1
}

# Graceful shutdown with a force fallback.
shutdown_vm() {
  local pc="$1"
  local tries=30
  if [ "$(vsh domstate "$pc" 2>/dev/null || echo unknown)" = "shut off" ]; then
    return
  fi
  vsh shutdown "$pc"
  for _ in $(seq 1 "$tries"); do
    [ "$(vsh domstate "$pc" 2>/dev/null || echo unknown)" = "shut off" ] && return 0
    sleep 2
  done
  echo "WARNING: $pc did not shut down cleanly — forcing." >&2
  vsh destroy "$pc"
}

# Move the PC's single NIC from the staging to the production network,
# keeping the same MAC and model (the machine's identity does not change).
recable_pc() {
  local pc="$1" mac="$2"
  vsh detach-interface "$pc" network --mac "$mac" --config
  vsh attach-interface "$pc" network --source "$PRODUCTION_NET" \
    --model "$PC_NIC_MODEL" --mac "$mac" --config
}

# Run a PC playbook from the staging server (the Ansible control node for the
# PCs — it has a foot in both networks). LC_ALL/LANG are pinned because the
# cloud-image staging server has no locale configured for non-interactive ssh
# sessions, which makes Ansible abort. In offline mode the PC's apt is pointed
# at the bundled repo via extra vars.
run_pc_playbook() {
  local play="$1"
  local extra=""
  if [ "$MODE" = offline ]; then
    extra="-e apt_offline=true -e apt_mirror=$APT_REPO_URL"
  fi
  ssh $(ssh_opts) "ops@$STAGING_HOST" \
    "cd /srv/egse-demo && LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook ansible/playbooks/$play $extra"
}

main "$@"