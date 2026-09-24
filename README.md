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

(TBD — filled in during milestone 2 once the demo scripts exist.)

## Getting Started

(TBD — how to bring up the demo environment.)

---

## Reference

Nitty-gritty details. Read this section when you need specifics.

### Layout

(TBD — filled in during milestone 2 once the implementation exists.)

### Requirements & Assumptions

#### Host

- Ubuntu 24.04 with KVM/libvirt (hardware virtualization enabled).
- Packages: `qemu-kvm`, `libvirt-daemon-system`, `virtinst`, `libguestfs-tools`,
  `cloud-image-utils`, `openssh-client`, `gnome-terminal` (demo terminals).
- libvirt `default` NAT network active; its DHCP range must not collide with the EGSE
  PCs' static production addresses.
- Network: the demo runs online when a stable network is reachable and falls back to a
  primed `lab/cache/` when it is not (see Core Concepts). Fetching the cloud image and
  packages requires internet at least once.

#### Assumptions

- The staging server and the EGSE PC are stand-ins for their real industrial
  counterparts: the isolated `staging-net` plays the factory/benchtop network, and the
  host's NAT network plays the production network.
- **Staging and production use non-overlapping ranges** (`10.10.0.0/24` vs
  `192.168.122.0/24`): the staging server bridges both, so overlap would confuse its
  routing.
- The EGSE PC uses BIOS firmware (not UEFI/Secure Boot).
- The EGSE PC's NIC is e1000 and its disk is IDE, so the tiny busybox deploy initramfs
  needs no extra kernel modules.
- The golden image is a minimal Ubuntu Server 24.04 (sshd, lab user + ssh key, DHCP
  networking, cloud-init disabled). It installs **no packages** — all tools/libraries
  are applied via apt in the production phase, keeping the bake offline-safe.
- The EGSE PC has a single network port; moving it from `staging-net` to the host
  network simulates the PC shipping to its production location. During staging it has
  no internet; it gains package access only after the handover.
- The Ansible inventory is the single source of truth for PC identity (MAC, staging IP,
  production IP, hostname).
- Single EGSE PC (`egse_pc-01`); adding more PCs only requires new inventory entries.

### Milestones

See [ROADMAP.md](./ROADMAP.md) for the project tracker with milestones and tasks.