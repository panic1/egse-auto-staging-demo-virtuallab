#!/usr/bin/env bash
# Install (or uninstall) the host prerequisites for the virtual lab demo.
#
# Core demo concept: the demo needs nothing but a standard Ubuntu 24.04 host
# with KVM. Run this once on any machine you want to present the demo from
# (e.g. a clean customer-provided laptop). It is idempotent — safe to re-run.
#
# To undo cleanly, the install step records exactly what it changed — the
# packages it actually installed and the groups it actually added — in
# lab/install_prereqs.state. --uninstall reverses exactly that, so it never
# removes software that was already on the machine.
#
# Usage:
#   sudo ./scripts/install_prereqs.sh              # install
#   sudo ./scripts/install_prereqs.sh --uninstall  # undo what was installed

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$REPO_ROOT/lab/install_prereqs.state"

REQUIRED_PACKAGES=(
  qemu-kvm
  libvirt-daemon-system
  virtinst
  libguestfs-tools
  cloud-image-utils
  ansible
  rsync
  curl
  openssh-client
  gnome-terminal
  # busybox-static provides the static busybox the PXE deploy initramfs is
  # built from (it replaces/conflicts with the dynamic 'busybox' package).
  busybox-static
  zstd
)

usage() {
  echo "Usage: sudo $0 [--uninstall|-u] [--help|-h]" >&2
  echo "  (default)    install the host prerequisites" >&2
  echo "  --uninstall  remove exactly what the install step added (packages," >&2
  echo "               libvirtd, group access) using lab/install_prereqs.state" >&2
}

ACTION="install"
case "${1:-}" in
  -u | --uninstall) ACTION="uninstall" ;;
  -h | --help) usage; exit 0 ;;
  "") ACTION="install" ;;
  *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
esac

# Front check: this script modifies the system, so it must run with root
# privileges (real root, or via sudo). The `sudo` on the command line handles
# the password prompt; this script never prompts or invokes sudo itself.
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: this script needs root privileges — run it with sudo:" >&2
  echo "  sudo $0 [--uninstall]" >&2
  exit 1
fi

# The real (sudoing) user gets libvirt/kvm group access. As plain root there
# is no SUDO_USER to grant those groups to.
LIBVIRT_GROUP_USER="${SUDO_USER:-}"
if [ "$ACTION" = install ] && [ -z "$SUDO_USER" ]; then
  echo "WARNING: running as plain root; no user will be added to the libvirt/kvm groups." >&2
fi

# Load what a previous install recorded (empty strings if nothing recorded).
read_state() {
  INSTALLED_PACKAGES=""
  ADDED_GROUPS=""
  if [ -f "$STATE_FILE" ]; then
    # shellcheck source=/dev/null
    . "$STATE_FILE"
  fi
}

# Persist the cumulative record of what this script has changed.
write_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  {
    echo "# Managed by scripts/install_prereqs.sh — records what was installed"
    echo "# so --uninstall can undo exactly that. Safe to delete."
    echo "INSTALLED_PACKAGES=\"$1\""
    echo "ADDED_GROUPS=\"$2\""
  } > "$STATE_FILE"
}

# Turn a set of whitespace-separated words into a sorted, deduped, single-line set.
normalize() {
  printf '%s\n' "$@" | sed '/^$/d' | sort -u | tr '\n' ' '
}

install() {
  if [ ! -e /dev/kvm ]; then
    echo "WARNING: /dev/kvm not found — enable virtualization in the BIOS/UEFI." >&2
  fi

  # Only install what is missing, and remember what that was.
  local to_install=()
  local pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      to_install+=("$pkg")
    fi
  done

  if [ "${#to_install[@]}" -gt 0 ]; then
    echo "Installing packages: ${to_install[*]}"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${to_install[@]}"
  else
    echo "All required packages are already installed."
  fi

  echo "Starting the libvirt daemon ..."
  systemctl enable --now libvirtd

  # Add the real user to the libvirt/kvm groups, tracking which we actually added.
  local added_groups=()
  if [ -n "$LIBVIRT_GROUP_USER" ]; then
    local grp
    for grp in libvirt kvm; do
      if ! id -nG "$LIBVIRT_GROUP_USER" | tr ' ' '\n' | grep -qx "$grp"; then
        usermod -aG "$grp" "$LIBVIRT_GROUP_USER"
        added_groups+=("$grp")
      fi
    done
  fi

  # Merge with anything recorded by a previous run.
  read_state
  # shellcheck disable=SC2086
  write_state "$(normalize $INSTALLED_PACKAGES "${to_install[@]}")" \
              "$(normalize $ADDED_GROUPS "${added_groups[@]}")"

  echo
  echo "Done. Recorded what was installed in lab/install_prereqs.state."
  echo "The group changes apply on your next login (or: newgrp libvirt)."
  echo "Then bring the lab up with: ./scripts/setup.sh"
}

uninstall() {
  read_state

  if [ -z "$INSTALLED_PACKAGES" ] && [ -z "$ADDED_GROUPS" ]; then
    echo "Nothing recorded to undo (no state file at lab/install_prereqs.state)."
    echo "If prerequisites were installed before tracking existed, remove them manually."
    return 0
  fi

  if [ -n "$INSTALLED_PACKAGES" ]; then
    echo "Removing packages installed by this script: $INSTALLED_PACKAGES"
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get remove -y $INSTALLED_PACKAGES
  fi

  # Only stop the daemon if this script installed it.
  if printf '%s\n' $INSTALLED_PACKAGES | grep -qx libvirt-daemon-system; then
    echo "Stopping and disabling the libvirt daemon ..."
    systemctl disable --now libvirtd 2>/dev/null || true
  fi

  if [ -n "$ADDED_GROUPS" ] && [ -n "$LIBVIRT_GROUP_USER" ]; then
    local grp
    for grp in $ADDED_GROUPS; do
      gpasswd -d "$LIBVIRT_GROUP_USER" "$grp" 2>/dev/null || true
    done
    echo "Removed $LIBVIRT_GROUP_USER from: $ADDED_GROUPS"
  fi

  rm -f "$STATE_FILE"
  echo
  echo "Done. The group changes apply on your next login."
  echo "Note: VM definitions and lab/ artifacts are left untouched."
}

if [ "$ACTION" = uninstall ]; then
  uninstall
else
  install
fi