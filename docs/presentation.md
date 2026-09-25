# EGSE Auto-Staging Demo — Presenter's Guide

Talking points and a phase-by-phase script for presenting the demo. The
structure mirrors what `demo.sh` prints, so you can follow along one-to-one.
Read [README.md](../README.md) first for the full technical detail.

---

## The one-sentence pitch

> Industrial PCs arrive in the field as bare machines. This demo shows how one
> can be staged, installed, and configured **fully automatically** — no
> technician, no USB stick, no manual steps — from a bare box to a verified,
> working machine.

## The mental model to plant early

| Real world | The demo |
|---|---|
| Freshly delivered industrial PC | a bare **VM** (`egse_pc-01`) |
| The lab/bench that preps PCs | the **staging server** VM |
| Factory bench network | **`staging-net`** (isolated) |
| The plant production network | **`production-net`** (NAT) |
| Shipping the PC to its site | re-cabling the PC's single NIC at **handover** |

Everything is a VM on one laptop, but the vocabulary is the real-world analogy.

---

## Before the demo (preparation checklist)

1. Fresh host, then bring the lab up online:
   ```sh
   sudo ./scripts/install_prereqs.sh   # re-login / newgrp libvirt after
   ./scripts/setup.sh                  # bakes image, creates staging server
   ```
   `setup.sh` also builds the offline apt repo (see the offline section).
2. For a narrated, paused run make sure the inventory defaults are on:
   ```yaml
   demo_pause: true            # press Enter between stages
   open_terminal_on_setup: true
   open_terminal_on_demo: true
   ```
3. Decide online vs. offline (offline section below).
4. Have `virsh console egse_pc-01` ready as the "window into the machine"
   during the PXE install — it shows the deploy tool working.

---

## Opening (before running `./scripts/demo.sh`)

Say:

> "An industrial PC is usually delivered without an OS. To bring it into
> service you'd install from media, configure networking, load the software
> stack, and test it — by hand, for every machine. This demo automates that
> whole lifecycle. The key idea: **one staging server prepares the PC; a baked
> golden image is installed over the network; configuration is applied in two
> phases — factory, then production — and the result is verified.**"

Point at the two networks concept (or the `staging-server` VM in the VM manager):
> "The staging server has two NICs: one on the **staging** network, one on the
> **production** network. The PC will start on the staging network and later be
> moved — shipped — to production. The staging server never changes network, so
> it stays the control point the whole time."

Run `./scripts/demo.sh`.

---

## Phase-by-phase script

Follow the `==> n/4 …` lines that `demo.sh` prints.

### 1/4 — STAGE

> "First we create the PC exactly as it would arrive from the factory: **an
> empty disk, no OS, booting from the network**. One NIC, BIOS firmware, a
> deliberately simple network card and disk — so the installer we're about to
> boot stays tiny."

Show the VM being created.

### 2/4 — INSTALL

> "The PC boots. On the staging network, **dnsmasq** on the staging server
> answers DHCP and hands it the **PXE boot files**: a pinned kernel and a tiny
> busybox initramfs — our deploy tool. That tool is the whole installer: it
> loads the network driver, gets an address, **downloads a pre-baked golden
> image over HTTP and writes it to the disk**. Then it powers the machine off."

> "The golden image is the OS 'recipe' — a stock Ubuntu with the lab user and
> ssh key baked in. No packages, no bloat: everything else happens later, in
> the phase that actually needs the network."

If you have the console open, point at the deploy messages (kernel boot, the
busybox `EGSE deploy:` lines).

When it comes back up:
> "The PC now boots normally from its disk. It's a real OS, and it asks for an
> address on the staging network."

### 3/4 — CONFIGURE (factory)

> "Now the PC is reachable, Ansible — running **on the staging server** — applies
> the factory configuration: it sets the hostname, regenerates the ssh host
> keys, and **writes the production network settings but does not apply them
> yet**. The PC is being prepared for its real location before it ships."

### 3/4 — HANDOVER

> "This is the shipping moment. The PC's **single network port is moved** from
> the staging network to the production network — the same NIC, the same
> machine, just re-cabled to where it will actually live. When it reboots, it
> comes up on its **static production address**."

Highlight: this is why the PC has only one port and why the networks don't
overlap — it really does change "location".

### 4/4 — CONFIGURE + VERIFY (production)

> "On the production network the PC finally gets its real workload: the package
> repositories, **OS updates**, and the EGSE software stack. Then the playbook
> **verifies** the end state — it doesn't just hope it worked, it asserts it."

Read the verification summary aloud:
```
hostname  = egse-pc-01
address   = 10.10.122.21 (expected 10.10.122.21)
netplan   = ok
ssh keys  = regenerated
packages  = git, curl, htop, python3-requests
updates   = up to date
```

> "Bare machine → configured, verified machine. No manual steps."

---

## Key concepts to reinforce

- **Golden image + tiny deploy tool.** Instead of a full installer, we install a
  pre-baked image with a ~30-line busybox initramfs. Simple, deterministic,
  offline-safe. ("The installer is not installed — it's a disposable tool.")
- **Two-phase configuration.** Factory config on the staging network (identity,
  security, network plans) vs. production config after handover (software +
  updates). Mirrors real commissioning.
- **Control node that never moves.** The staging server bridges both networks,
  so Ansible always runs from the same place.
- **Config over flags.** Everything (IPs, MACs, sizes, demo pacing) lives in the
  Ansible inventory — the single source of truth. No CLI flags, so every run is
  reproducible.
- **Idempotent.** Setup/teardown can be re-run from a clean state.

## Offline variant (Milestone 3)

> "This also runs with no internet." Setup runs online once and bundles the
> PC's software into a small apt repo served by the staging server. Then cut
> the network and run `demo.sh`: it auto-detects the missing network, prints
> **`Mode: offline`**, and the PC installs its software from that bundled repo
> instead of the Ubuntu archive.

If the demo should end offline: run `setup.sh` online, disconnect, run
`demo.sh`, and call out the "Mode: offline" line.

## Teardown / reset between shows

```sh
./scripts/teardown.sh
```

With `teardown_clean: true` (default) this removes the cache, golden image,
offline repo, and keys — a truly clean slate. Set `teardown_clean: false` to
keep the offline assets for faster re-runs. Then `setup.sh` again for the next
show.

## Likely questions & answers

- **"Why a VM?"** — It's a stand-in so the demo runs on one laptop; every
  concept maps 1:1 to a real industrial PC and a real staging lab.
- **"Is the deploy tool a Linux distro?"** — No: it's a pinned Ubuntu kernel +
  static busybox + one network driver, assembled into a small initramfs.
- **"Doesn't dnsmasq leak DHCP onto the production network?"** — No: it is
  bound to the staging interface only (`interface=…` + `bind-interfaces`), and
  the production network has no DHCP at all.
- **"What if I want more PCs?"** — Add an entry to the inventory; the PXE
  reservations, DHCP, and the demo loop are all inventory-driven.
- **"Is this production-grade?"** — No, it's a **baseline example**: the
  concepts (golden image, network PXE install, two-phase config, verify) are
  the engineering pattern; the real system would harden this (signing, GPG,
  auth, monitoring).