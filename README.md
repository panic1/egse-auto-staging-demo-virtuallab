# EGSE Auto-Staging Demo — Virtual Lab

A virtual lab demo that shows how an industrial PC can be staged, installed, and
configured automatically **from scratch**. In this demo, the industrial PC is
represented as a virtual machine (VM).

## Overview

The demo walks through the full lifecycle of bringing an industrial PC into service
without manual intervention:

1. **Stage** — provision a bare VM that represents a freshly delivered industrial PC.
2. **Install** — apply the operating system and base software unattended.
3. **Configure** — apply the target configuration (networking, roles, EGSE application
   setup) automatically.
4. **Verify** — confirm the machine reached its expected end state.

This repository is a **demo and proof of concept**, not a production deployment
system. Its goal is to demonstrate the *concept* of fully automatic
staging/installation/configuration of industrial PCs, and to be easily presented and
understood by an audience.

## Core Concepts

- **The VM is a stand-in for an industrial PC.** Script names, docs, and output use the
  real-world analogy (stage → install → configure → verify), not generic "VM
  provisioning" language.
- **From scratch.** The demo starts from a bare machine and ends in a configured,
  verified state with no manual steps.
- **Idempotent.** Setup can be re-run from a clean state without manual cleanup.
- **Teaching material.** Demo scripts are simple, readable, and documented to explain
  the concept they demonstrate.

## Demo Flow

The demo runs entirely from `scripts/`, driven by the inventory:

1. **`setup.sh`** brings the lab up (idempotent):
   1. Bakes the **golden image** (`generate_golden_image.sh`): the cached Ubuntu
      cloud image + `ops` user + shared ssh key, DHCP netplan, baked ssh host
      keys, cloud-init disabled. It also builds the **PXE deploy tool**: a
      pinned kernel + tiny busybox initramfs.
   2. Creates the **staging server** VM (`setup_virtuallab.sh`) with two NICs
      (production net + isolated staging net) and the demo networks.
   3. Syncs the repo to the staging server and configures it with Ansible
      (`staging.yml`): **dnsmasq** (DHCP + TFTP + PXE on the staging interface),
      the PXE boot files, and the HTTP server for the golden image.

2. **`demo.sh`** stages each PC from the inventory, in four stages:
   1. **Stage** — creates the bare PC VM (empty disk, e1000 NIC on the staging
      net, BIOS firmware, PXE-first boot order).
   2. **Install** — the PC PXE-boots; dnsmasq hands it the deploy kernel +
      initramfs, which downloads the golden image over HTTP and writes it to
      the disk, then powers off. The demo flips the boot order and boots the PC
      normally.
   3. **Configure** — Ansible (from the staging server, the control node for the
      PCs) applies the **factory configuration** on the staging network:
      hostname, ssh host key regeneration, and the static production netplan
      (written but not applied). Then the PC is **re-cabled** (its single NIC is
      moved to the production network — simulating shipping) and rebooted onto
      its static production address.
   4. **Configure + Verify** — Ansible applies the **production configuration**:
      apt mirror setup, OS updates, and the EGSE software stack
      (`git`, `curl`, `htop`, `python3-requests`), then **verifies** the end
      state (hostname, production address live, netplan in place, ssh keys
      regenerated, packages present, nothing upgradable).

3. **`teardown.sh`** destroys the VMs and networks and cleans up lab artifacts
   (keeping the cache/golden image unless `teardown_clean: true`).

Every script is documented to explain the concept it demonstrates. Run the demo
interactively with `demo_pause: true` (press-Enter narration) and, optionally,
`open_terminal_on_demo: true` for live show-and-tell ssh terminals into the PC.

## Getting Started

Everything runs from this repo on an Ubuntu 24.04 host. All demo behavior is
configured in the Ansible inventory (`inventory/group_vars/all.yml`) — never
via command-line flags — so runs are reproducible.

### 1. Install the host prerequisites (once)

```sh
sudo ./scripts/install_prereqs.sh
```

This installs the packages the demo needs (KVM/libvirt, virtinst,
libguestfs-tools, ansible, busybox-static for the deploy initramfs, …), starts
the libvirt daemon, and adds your user to the `libvirt`/`kvm` groups.
**Log out and back in** (or run `newgrp libvirt`) for the group changes to
apply. Undo it later with `sudo ./scripts/install_prereqs.sh --uninstall`.

### 2. Bring the lab up

```sh
./scripts/setup.sh
```

This bakes the golden image (if needed), defines the two demo networks and the
staging server VM, syncs the repo to the staging server, and configures it with
Ansible (dnsmasq DHCP/TFTP/PXE, the HTTP server, the PXE boot files). When
online, it also bundles the PC's EGSE packages into a small apt repo
(`scripts/fetch_dependencies.sh`) so the **demo can later run with no network**.
It is idempotent — safe to re-run.

### 3. Run the demo

```sh
./scripts/demo.sh
```

This stages each PC from the inventory through the full lifecycle: it creates
the bare PC VM, PXE-installs the golden image, applies the factory
configuration on the staging network, re-cables the PC to the production
network (the "shipping" handover), and finishes with the production software,
updates, and a verification of the end state.

The demo is interactive by default: `demo_pause: true` pauses between stages
for narration (press Enter), and `open_terminal_on_setup` / `open_terminal_on_demo`
open live show-and-tell ssh terminals into the machines. Set them to `false`
in `inventory/group_vars/all.yml` for an unattended run.

**Offline demo.** Only the demo has an offline mode — setup stays online. After
an online `setup.sh` (which primes the offline apt repo), you can disconnect the
network and `demo.sh` still works: it auto-detects the missing network and the
PC's production phase installs the EGSE software stack from the bundled repo
(`lab/apt-repo/`) served by the staging server, instead of from
`archive.ubuntu.com`.

### 4. Tear down

```sh
./scripts/teardown.sh
```

Destroys the VMs and the demo networks and cleans up lab artifacts. By default
(`teardown_clean: true`) it also removes the dependency cache, golden image,
deploy assets, and ssh keys; set `teardown_clean: false` to keep them (e.g. so
the offline cache stays primed across repeated runs).

## Reference

Nitty-gritty details. Read this section when you need specifics.

### Layout

- `inventory/` — Ansible inventory, the **single source of truth**: machine
  identity (MAC, staging/production IP, hostname in `host_vars/`), VM sizing,
  network layout, and demo behavior (`group_vars/all.yml`, `egse_pcs.yml`,
  `staging.yml`).
- `ansible/` — playbooks and roles:
  - `staging_server` — dnsmasq (DHCP+TFTP+PXE), PXE boot files, HTTP server.
  - `egse_pc` — `configure.yml` (factory config on the staging net),
    `production.yml` (apt mirror, updates, EGSE stack), `verify.yml` (end-state
    assertions).
  - `egse_pc-staging.yml` / `egse_pc-production.yml` — select the phase via
    `tasks_from` (an `import_role` parameter; the `roles:` keyword ignores it).
- `scripts/` — the demo lifecycle:
  - `setup.sh`, `setup_virtuallab.sh`, `generate_golden_image.sh`, `demo.sh`,
    `teardown.sh`, `install_prereqs.sh`, and `lib/common.sh` (shared helpers:
    `labvar`, mode detection, ssh helpers, `list_pcs`, `step`/`demo_pause`).
- `lab/` — gitignored runtime artifacts: VM disks, seed ISOs, the golden image
  (`lab/golden.img`), the PXE deploy assets (`lab/deploy/`), the dependency
  cache (`lab/cache/`), and the demo ssh keys (`lab/keys/`).

### Requirements & Assumptions

#### Host

- Ubuntu 24.04 with KVM/libvirt (hardware virtualization enabled).
- Packages: `qemu-kvm`, `libvirt-daemon-system`, `virtinst`, `libguestfs-tools`,
  `cloud-image-utils`, `ansible`, `rsync`, `curl`, `openssh-client`,
  `gnome-terminal` (demo terminals), `busybox-static` (the deploy initramfs),
  `zstd` — install them with `sudo ./scripts/install_prereqs.sh`.
- The demo uses the **system libvirt daemon** (`qemu:///system`) — the session daemon
  cannot create the bridge networks the demo needs. `install_prereqs.sh` adds your user
  to the `libvirt` and `kvm` groups (re-login or `newgrp libvirt` after).
- VM disks and seed ISOs are created as volumes in libvirt's `default` storage pool
  (`/var/lib/libvirt/images`), so the `libvirt-qemu` user can access them with **no
  permission changes** to this repo or your home directory.
- The demo defines its own two networks in the system daemon (`production-net` on
  `10.10.122.0/24` — **no DHCP**, every device static — and `staging-net` on
  `10.10.0.0/24`); it does not touch the host's `default` network.
- Network: **setup runs online** — it fetches the cloud image and build assets and
  provisions the staging server. The **demo can then run offline**: online setup
  bundles the PC's EGSE packages into a small apt repo (`lab/apt-repo/`, via
  `scripts/fetch_dependencies.sh`) that the staging server serves to the PC, so
  `demo.sh` works with no internet. Fetching everything requires internet at least
  once (during setup).

#### Assumptions

- The staging server and the EGSE PC are stand-ins for their real industrial
  counterparts: the isolated `staging-net` plays the factory/benchtop network, and the
  NAT `production-net` plays the production network.
- **Staging and production use non-overlapping ranges** (`10.10.0.0/24` vs
  `10.10.122.0/24`): the staging server bridges both, so overlap would confuse its
  routing.
- The EGSE PC uses BIOS firmware (not UEFI/Secure Boot).
- The EGSE PC's NIC is e1000 and its disk is IDE, so the tiny busybox deploy initramfs
  needs no extra kernel modules.
- The golden image is a minimal Ubuntu Server 24.04 (sshd, lab user + ssh key, DHCP
  networking, cloud-init disabled). It installs **no packages** — all tools/libraries
  are applied via apt in the production phase, keeping the bake offline-safe. It keeps
  the cloud image's partition layout and ~2.7G root (a `virt-resize` grow breaks the
  boot on noble); production disk hygiene (`apt autoremove`/clean) keeps the root from
  filling up.
- The EGSE PC has a single network port; moving it from `staging-net` to the
  production network simulates the PC shipping to its production location. During
  staging it has no internet; it gains package access only after the handover.
- The Ansible inventory is the single source of truth for PC identity (MAC, staging IP,
  production IP, hostname).
- Single EGSE PC (inventory key / VM name `egse_pc-01`, hostname `egse-pc-01` —
  hostnames allow no underscores); adding more PCs only requires new inventory
  entries.

### Milestones

See [ROADMAP.md](./ROADMAP.md) for the project tracker with milestones and tasks.