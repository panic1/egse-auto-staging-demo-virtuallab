# EGSE Auto-Staging Demo — Presenter's Guide

Talking points and a phase-by-phase script for presenting the demo. The
structure mirrors what `demo.sh` prints, so you can follow along one-to-one.
Read [README.md](../README.md) first for the full technical detail.

---

## The one-sentence pitch

> Industrial PCs arrive in the field as bare machines. This demo shows how one
> can be staged, installed, and configured **fully automatically** — no USB
> stick, no disk clone, no manual steps — from a bare box to a verified, working
> machine, kept in sync with automatic updates.

## The mental model to plant early

| Real world | The demo |
|---|---|
| Freshly delivered industrial PC | a bare **VM** (`egse_pc-01`) |
| The lab/bench that preps PCs | the **staging server** VM |
| Factory bench network | **`staging-net`** (isolated) |
| Office lab network | **`production-net`** (NAT) |
| Moving the PC to the EGSE rack | re-cabling the PC's single NIC at **handover** |

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
   egse_pc_scope: [egse_pc-01] # one PC; 'all' or [egse_pc-02] for more
   ```
   To rehearse a single PC, leave `egse_pc_scope: [egse_pc-01]`; set it to `all`
   to stage every PC in one run.
3. Decide online vs. offline (offline section below).
4. Have `virsh console egse_pc-01` ready as the "window into the machine"
   during the PXE install — it shows the deploy tool working.

---

## Opening (before running `./scripts/demo.sh`)

Say:

> "An industrial PC is usually delivered without an OS. To bring it into
> service you'd install from media, configure networking, load the software
> stack, and test it — by hand, for every machine. And that's before the ongoing
> job of keeping each machine **up to date** as software releases change. This
> demo automates that whole lifecycle. The key idea: **one staging server
> prepares the PC; a baked golden image is installed over the network;
> configuration is applied in two phases — factory, then production — and the
> result is verified.**"

Point at the two networks concept (or the `staging-server` VM in the VM manager):
> "The staging server has two NICs: one on the **staging** network, one on the
> **production** network, so it bridges both. The PC will start on the isolated
> staging network and later be moved — cabled into the EGSE rack — onto
> production. The staging server never changes network, so it stays the control
> point the whole time."

Call out the one *dangerous* piece:
> "The staging server runs the DHCP server, but **only on the staging side**.
> The production network carries no DHCP at all — a rogue DHCP server there
> would be a real incident. dnsmasq is bound to the staging interface only, so
> it can never leak onto production."

Run `./scripts/demo.sh`.

`demo.sh` stages the PCs named by `egse_pc_scope` (default `[egse_pc-01]`)
through the full lifecycle — the same inventory that defines their MACs and
addresses, so repeatability is the point. To stage the second PC (`egse_pc-02`)
in a later run, set `egse_pc_scope: [egse_pc-02]` (or `all`) — no `setup.sh`
needed, its dnsmasq reservation is already primed.

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
> its authorized ssh public key baked in. No packages, no bloat: everything else
> happens later, in the phase that actually needs the network."

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

### 3/4 — HANDOVER (EGSE rack integration)

> "This is the integration moment: the PC leaves the bench and goes into the
> EGSE rack. Its **single network port is re-cabled** from the staging network
> to the production network — the same NIC, the same machine, just cabled to
> where it will actually live. When it reboots, it comes up on its **static
> production address**."

Highlight: this is why the PC has only one port and why the networks don't
overlap — it really does change "location".

### 4/4 — CONFIGURE + VERIFY (production)

> "On the production network the PC finally gets its real workload: the package
> repositories, **OS updates**, and the EGSE software stack — here just
> placeholders (git, curl, htop, python3-requests) standing in for the real
> packages. Then the playbook **verifies** the end state — it doesn't just hope
> it worked, it asserts it."

Read the verification summary aloud:
```
hostname  = egse-pc-01
address   = 10.10.122.21 (expected 10.10.122.21)
netplan   = ok
ssh keys  = regenerated
packages  = git, curl, htop, python3-requests
updates   = up to date
```

(Those packages are placeholders in the demo — the point is that the end state
is asserted, not assumed.)

(The same summary prints for every PC in the run's scope; set `egse_pc_scope`
to `all` (or `[egse_pc-02]`) in a later run to stage the second PC too.)

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
- **DHCP only where it belongs.** The staging server's dnsmasq serves DHCP
  **only on the staging interface**; the production network has none, so it can
  never leak into — or disrupt — production.
- **Config over flags.** Everything (IPs, MACs, sizes, demo pacing, **which PCs
  are staged**) lives in the Ansible inventory — the single source of truth. No
  CLI flags, so every run is reproducible. `egse_pc_scope` picks the PCs for a
  run; `demo_pause`/`open_terminal_on_demo` control pacing.
- **Idempotent.** Setup/teardown can be re-run from a clean state.

## Offline variant (Milestone 3)

> "This also runs with no internet." Run `setup.sh` online once: it bundles the
> PC's software *and* the staging server's own packages into a small apt repo.
> Then cut the network. `setup.sh` still works — it reuses the cached cloud
> image, golden image, and deploy assets (nothing is rebuilt), recreates the
> staging server, and installs its packages from the bundle. `demo.sh` then
> auto-detects the missing network, prints **`Mode: offline`**, and the PC
> installs its software from that bundled repo instead of the Ubuntu archive.

This is the travel workflow: online setup + `teardown.sh` (`teardown_clean:
false`, which keeps the cache/golden image/deploy assets/apt repo) at home,
then offline `setup.sh` + `demo.sh` at the meeting. Teardown destroys the
staging VM to save battery, so the offline setup rebuilds it from cache.

## Teardown / reset between shows

```sh
./scripts/teardown.sh
```

By default (`teardown_clean: false`) this **keeps** the cache, golden image,
deploy assets, offline repo, and keys, so the lab can be brought back up offline
and re-runs don't re-fetch everything. Set `teardown_clean: true` for a truly
clean slate. Then `setup.sh` again for the next show.

## Likely questions & answers

- **"Why a VM?"** — It's a stand-in so the demo runs on one laptop; every
  concept maps 1:1 to a real industrial PC and a real staging lab.
- **"Is the deploy tool a Linux distro?"** — No: it's a pinned Ubuntu kernel +
  static busybox + one network driver, assembled into a small initramfs.
- **"Doesn't dnsmasq leak DHCP onto the production network?"** — No: it is
  bound to the staging interface only (`interface=…` + `bind-interfaces`), and
  the production network has no DHCP at all.
- **"What if I want more PCs?"** — Add an entry to the inventory (`hosts.yml` +
  a `host_vars/egse_pc-0N.yml`); the PXE reservations, DHCP, and the demo loop
  are all inventory-driven. To bring up just the new one without touching a PC
  already running on production, set `egse_pc_scope: [egse_pc-0N]` — machines
  outside the scope are left alone.
- **"Is this production-grade?"** — No, it's a **baseline example**: the
  concepts (golden image, network PXE install, two-phase config, verify) are
  the engineering pattern; the real system would harden this (signing, GPG,
  auth, monitoring).