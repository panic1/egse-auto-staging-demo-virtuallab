#!/usr/bin/env bash
# Bake the golden image and build the PXE deploy assets.
#
# Core demo concept: the golden image is the operating system that gets
# installed onto an industrial PC. Here it is baked once, on the demo host,
# from the cached Ubuntu cloud image:
#
#   cloud image -> virt-customize (ops user + ssh key, DHCP netplan,
#                                  cloud-init disabled)
#               -> raw lab/golden.img   (the install payload, served over HTTP)
#
# NOTE: the cloud image's own partition layout and GRUB are used unchanged —
# virt-resize (expand/renumber) produces a non-bootable image on noble, so the
# golden image keeps the cloud image's root size (~2.7G; /boot is a separate
# partition). Production-phase disk hygiene (apt autoremove/clean) keeps the
# small root from filling up. cloud-init is disabled, so its first-boot ssh
# host key generation is replaced by baking the keys in (ssh-keygen -A).
#
# The golden image installs NO packages (the cloud image already ships sshd);
# the EGSE software stack is applied via apt in the production phase, which
# keeps the bake fully offline-safe.
#
# The second output is the PXE deploy TOOL (not installed anywhere — it only
# exists to install the golden image):
#
#   pinned Ubuntu kernel (vmlinuz) + busybox + one NIC driver module (e1000;
#   the IDE driver is built into the kernel) assembled into a tiny initramfs.
#   It boots briefly on the staging network, downloads lab/golden.img over
#   HTTP, writes it to disk, and powers off.
#
# Idempotent: re-running skips work whose output already exists. Delete
# lab/golden.img (and lab/deploy/) to rebuild. libguestfs cannot run as a
# non-root user, so the bake re-executes itself under passwordless sudo.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

# libguestfs (virt-resize/virt-customize) needs root on this host; re-exec the
# whole bake under passwordless sudo so ownership of the lab artifacts stays
# consistent. PATH is preserved so user-installed tools (e.g. ansible-inventory
# in ~/.local/bin) stay visible to the root-run script.
if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then
    exec sudo -n env "PATH=$PATH" "$0" "$@"
  else
    echo "ERROR: the golden-image bake needs root (libguestfs)." >&2
    echo "  Run with sudo, or enable passwordless sudo for this user." >&2
    exit 1
  fi
fi

GOLDEN_QCOW="$LAB_DIR/golden.qcow2"
GOLDEN_IMG="$LAB_DIR/golden.img"
DEPLOY_DIR="$LAB_DIR/deploy"
INITRD_DIR="$LAB_DIR/initramfs"

CLOUD_IMG_URL="$(labvar staging-server cloud_image_url)"
CLOUD_IMG="$CACHE_DIR/$(basename "$CLOUD_IMG_URL")"
DEPLOY_KERNEL_URL="$(labvar staging-server deploy_kernel_url)"
DEPLOY_MODULES_URL="$(labvar staging-server deploy_modules_url)"

# The HTTP server the deploy tool downloads the golden image from: the staging
# server's address on the isolated staging network (baked in at build time —
# the deploy tool is shared by all PCs, and they all pull the same image).
DEPLOY_SERVER="$(labvar staging-server staging_ip)"

# Kernel drivers the deploy initramfs must load to install the golden image.
#   e1000    - the PC's NIC (a module in the pinned kernel)
#   ata_piix - the PC's IDE disk controller (built INTO the kernel; nothing to
#              bundle — kept here as documentation)
DEPLOY_MODULES=(e1000)

main() {
  require_commands virt-customize qemu-img virt-filesystems \
    dpkg-deb depmod cpio gzip zstd curl ansible-inventory python3

  ensure_ssh_key

  if [ -f "$GOLDEN_IMG" ] && [ -f "$DEPLOY_DIR/vmlinuz" ] && [ -f "$DEPLOY_DIR/initramfs.gz" ]; then
    echo "Golden image and deploy assets already exist (delete lab/golden.img and lab/deploy/ to rebuild)."
    return 0
  fi

  build_golden_image
  build_deploy_assets

  # The bake re-executes under sudo, so its outputs (and the fetched cache
  # files) end up root-owned. Hand the lab artifacts back to the invoking
  # user so the demo scripts (rsync, ssh) work unchanged.
  if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER:" "$LAB_DIR"
  fi

  echo
  echo "Done:"
  echo "  - install payload:  $GOLDEN_IMG"
  echo "  - deploy assets:    $DEPLOY_DIR/{vmlinuz,initramfs.gz}"
}

# ---------------------------------------------------------------------------
# 1. The golden image
# ---------------------------------------------------------------------------
build_golden_image() {
  if [ -f "$GOLDEN_IMG" ]; then
    echo "Golden image exists; skipping (delete lab/golden.img to rebuild)."
    return
  fi

  echo "=== 1/2 Baking the golden image (this can take a few minutes) ==="

  # The cached cloud image is the pristine source — fetch it if it is not
  # there yet (clean state / first run).
  fetch_or_fallback "$CLOUD_IMG_URL" >/dev/null

  # Start from a fresh copy of the cached cloud image — never modify the
  # cache. The cloud image's partition layout + GRUB are known-good and are
  # kept as-is: the root filesystem is grown on the PC's first boot (see the
  # --firstboot-command below) instead of with virt-resize, which produces a
  # non-bootable image on noble.
  echo "Copying the cached cloud image ..."
  qemu-img convert -O qcow2 "$CLOUD_IMG" "$GOLDEN_QCOW"

  echo "Customizing: lab user, ssh key, DHCP netplan, cloud-init disabled, serial getty ..."
  # The ops user (design decision: 'ops' must not match any group on the image
  # — see ROADMAP Task 3). cloud-init is disabled so the PC boots as a plain
  # Ubuntu machine — which also means cloud-init's first-boot ssh host key
  # generation never runs, so the keys are baked in here (ssh-keygen -A);
  # without them sshd refuses to start. The DHCP netplan matches the NIC by
  # its driver (e1000), so the baked image works regardless of the interface
  # name (ens3 on the i440fx machine, eth0 in the deploy tool, enp2s0 on q35).
  # netplan's match.name is a single glob, so driver matching is the
  # name-independent choice here. networkd-wait-online is disabled so the boot
  # never stalls on network readiness.
  cat > "$LAB_DIR/90-dhcp.yaml" <<'EOF'
network:
  version: 2
  ethernets:
    eth-dhcp:
      match:
        driver: e1000
      dhcp4: true
EOF
  virt-customize -a "$GOLDEN_QCOW" \
    --root-password locked \
    --run-command "useradd -m -s /bin/bash ops" \
    --ssh-inject ops:file:"$LAB_DIR/keys/egse-demo.pub" \
    --run-command "echo 'ops ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ops" \
    --touch /etc/cloud/cloud-init.disabled \
    --delete /etc/netplan/50-cloud-init.yaml \
    --upload "$LAB_DIR/90-dhcp.yaml:/etc/netplan/90-dhcp.yaml" \
    --run-command "systemctl enable serial-getty@ttyS0.service" \
    --run-command "systemctl disable systemd-networkd-wait-online.service" \
    --run-command "sed -i 's/quiet splash//g' /boot/grub/grub.cfg" \
    --run-command "ssh-keygen -A" \
    --append-line /etc/initramfs-tools/modules:e1000 \
    --run-command "update-initramfs -u" \
    >/dev/null

  # Serve a raw image so the deploy tool can dd it straight onto the PC's raw
  # disk (a qcow2 payload would need qemu-img on the bare PC, which it lacks).
  echo "Converting to a raw install payload ..."
  qemu-img convert -O raw "$GOLDEN_QCOW" "$GOLDEN_IMG"
  rm -f "$GOLDEN_QCOW" "$LAB_DIR/90-dhcp.yaml"
}

# ---------------------------------------------------------------------------
# 2. The PXE deploy tool (pinned kernel + busybox initramfs)
# ---------------------------------------------------------------------------
build_deploy_assets() {
  if [ -f "$DEPLOY_DIR/vmlinuz" ] && [ -f "$DEPLOY_DIR/initramfs.gz" ]; then
    echo "Deploy assets exist; skipping (delete lab/deploy/ to rebuild)."
    return
  fi

  echo "=== 2/2 Building the PXE deploy tool ==="
  rm -rf "$DEPLOY_DIR" "$INITRD_DIR"
  mkdir -p "$DEPLOY_DIR" "$INITRD_DIR"/{bin,etc,proc,sys,dev,modules}

  # 2a. The pinned kernel + modules: official Ubuntu .debs, extracted with
  #     dpkg-deb. Pinning a version makes the deploy tool reproducible and
  #     independent of the presenter's host kernel.
  local kdeb mdeb xdir kv
  kdeb="$(fetch_or_fallback "$DEPLOY_KERNEL_URL")"
  mdeb="$(fetch_or_fallback "$DEPLOY_MODULES_URL")"
  xdir="$LAB_DIR/deploy-src"
  rm -rf "$xdir"
  mkdir -p "$xdir"
  dpkg-deb -x "$kdeb" "$xdir"
  dpkg-deb -x "$mdeb" "$xdir"

  kv="$(basename "$xdir"/boot/vmlinuz-*)"
  kv="${kv#vmlinuz-}"   # e.g. 6.8.0-146-generic
  cp "$xdir/boot/vmlinuz-$kv" "$DEPLOY_DIR/vmlinuz"
  echo "Using pinned kernel $kv"

  # 2b. The NIC driver module(s). depmod generates modules.dep so we can
  #     resolve the module paths (and any dependencies). The modules are
  #     decompressed to plain .ko so busybox's insmod never sees kernel
  #     compression. Only e1000 is needed; the disk driver is built in.
  depmod -b "$xdir" "$kv" 2>/dev/null || true
  resolve_modules "$xdir/lib/modules/$kv/modules.dep"
  if [ ! -s "$DEPLOY_DIR/modules.list" ]; then
    echo "ERROR: could not resolve any deploy modules (pinned kernel problem?)." >&2
    exit 1
  fi

  # 2c. busybox — the entire userland of the deploy tool. A static binary so
  #     the initramfs needs no shared libraries.
  if [ ! -f /bin/busybox ]; then
    echo "ERROR: no static busybox at /bin/busybox (install busybox-static)." >&2
    exit 1
  fi
  cp /bin/busybox "$INITRD_DIR/bin/busybox"
  for applet in sh mount insmod udhcpc wget dd sync poweroff sleep ip ln ls cat mkdir grep head; do
    ln -sf busybox "$INITRD_DIR/bin/$applet"
  done

  # 2d. Copy the modules into the initramfs, decompressing .ko.zst as needed.
  local mpath src
  while read -r mpath; do
    [ -z "$mpath" ] && continue
    mkdir -p "$INITRD_DIR/modules/$(dirname "$mpath")"
    src="$xdir/lib/modules/$kv/$mpath"
    if [ -f "$src.zst" ]; then
      zstd -dfq "$src.zst" -o "$INITRD_DIR/modules/$mpath"
    elif [ -f "$src" ]; then
      cp "$src" "$INITRD_DIR/modules/$mpath"
    else
      echo "WARNING: module '$mpath' not found in the extracted kernel." >&2
    fi
  done < "$DEPLOY_DIR/modules.list"
  cp "$DEPLOY_DIR/modules.list" "$INITRD_DIR/modules.list"

  # 2e. The deploy init script and a minimal udhcpc script.
  write_init_script
  write_udhcpc_script

  # 2f. Package the initramfs (gzip'd newc cpio — the kernel's early-userspace
  #     format) and clean up the scratch dirs.
  ( cd "$INITRD_DIR" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -9 > "$DEPLOY_DIR/initramfs.gz" )
  rm -rf "$INITRD_DIR" "$xdir"
}

# Resolve the requested deploy modules (plus dependencies) from modules.dep,
# deps first, deduplicated, preserving order. Writes lab/deploy/modules.list.
resolve_modules() {
  local depfile="$1"
  local name line file deps d
  : > "$DEPLOY_DIR/modules.list"
  for name in "${DEPLOY_MODULES[@]}"; do
    line="$(grep -E "^[^:]*/${name}\.ko" "$depfile" | head -n1 || true)"
    if [ -z "$line" ]; then
      echo "NOTE: module '$name' is not shipped with the pinned kernel (built-in?) — nothing to bundle."
      continue
    fi
    file="${line%%:*}"
    deps="${line#*:}"
    deps="${deps# }"   # strip the space after the colon
    for d in $deps; do
      echo "${d%.zst}" >> "$DEPLOY_DIR/modules.list"
    done
    echo "${file%.zst}" >> "$DEPLOY_DIR/modules.list"
  done
  awk '!seen[$0]++' "$DEPLOY_DIR/modules.list" > "$DEPLOY_DIR/modules.list.tmp"
  mv "$DEPLOY_DIR/modules.list.tmp" "$DEPLOY_DIR/modules.list"
}

# The deploy tool's PID-1: load the NIC driver, get an address via DHCP, then
# stream the golden image from the staging server straight onto the disk.
write_init_script() {
  cat > "$INITRD_DIR/init" <<EOF
#!/bin/sh
# EGSE auto-staging deploy tool.
#
# Core concept: this is the PC's "installer". It boots briefly on the
# isolated staging network, downloads the pre-baked golden image from the
# staging server over HTTP, and writes it to the disk. It then powers off so
# the demo can boot the machine normally.
#
# ${DEPLOY_SERVER} is the staging server's address on the staging network,
# baked in at build time (scripts/generate_golden_image.sh).
export PATH=/bin:/sbin

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "EGSE deploy: loading NIC driver(s) ..."
for m in \$(cat /modules.list); do
  insmod "/modules/\$m"
done
sleep 2

# The interface name is unpredictable (ens3/enp0s2/...): take the first one.
IFACE="\$(ls /sys/class/net | grep -v '^lo\$' | head -n1)"
echo "EGSE deploy: using interface \$IFACE"
ip link set "\$IFACE" up

echo "EGSE deploy: waiting for DHCP ..."
for _ in 1 2 3 4 5 6 7 8 9 10; do
  udhcpc -i "\$IFACE" -s /etc/udhcpc.script -q -n 2>/dev/null && break
  sleep 1
done
if ! ip -4 addr show dev "\$IFACE" | grep -q 'inet '; then
  echo "EGSE deploy: FATAL - no DHCP lease on \$IFACE" >&2
  exec sh
fi

if [ ! -e /dev/sda ]; then
  echo "EGSE deploy: FATAL - no IDE disk /dev/sda" >&2
  exec sh
fi

echo "EGSE deploy: downloading golden image from ${DEPLOY_SERVER} ..."
# Stream straight to the disk: the image is several GB and must never be
# staged in the initramfs's RAM.
wget -O- "http://${DEPLOY_SERVER}/golden.img" 2>/dev/null | dd of=/dev/sda bs=4M conv=fsync

echo "EGSE deploy: image written; powering off ..."
sync
poweroff -f
EOF
  chmod +x "$INITRD_DIR/init"
}

# Minimal udhcpc script: busybox udhcpc calls us with deconfig/bound and
# exports $interface, $ip, $mask, $router (see busybox examples/simple.script).
write_udhcpc_script() {
  cat > "$INITRD_DIR/etc/udhcpc.script" <<'EOF'
#!/bin/sh
case "$1" in
  deconfig)
    ip addr flush dev "$interface" 2>/dev/null
    ;;
  bound)
    ip addr add "$ip/${mask:-24}" dev "$interface"
    ip link set "$interface" up
    [ -n "$router" ] && ip route add default via "$router" 2>/dev/null || true
    ;;
esac
EOF
  chmod +x "$INITRD_DIR/etc/udhcpc.script"
}

main "$@"