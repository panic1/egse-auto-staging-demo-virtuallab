---
marp: true
theme: default
size: 16:9
paginate: true
title: EGSE Auto-Staging Demo
description: Staging, installing, and configuring an industrial PC fully automatically
---

<!-- _paginate: false -->

# EGSE Auto-Staging

**Bringing an industrial PC into service — fully automatically**

Stage · Install · Configure · Verify

<!-- A live demo: an industrial PC (a VM) goes from a bare machine to a
     configured, verified machine with no manual steps. -->

---

## Agenda

1. The problem — bare industrial PCs, manual staging
2. The idea — automate the whole lifecycle
3. The lab — what we build
4. The lifecycle, live: **Stage → Install → Configure → Verify**
5. Offline fallback
6. Key concepts
7. Baseline example & Q&A

---

## The problem

Industrial PCs ship as **bare machines** — no OS, nothing.

To commission one today:

- Install an OS from media, by hand
- Configure networking per site
- Load the EGSE software stack
- Verify it actually works

…for **every single machine**. Slow, error-prone, not repeatable.

---

## The idea

> One **staging server** prepares the PC; a pre-baked **golden image** is
> installed over the network; configuration is applied in **two phases**
> (factory, then production); and the result is **verified**.

No technician, no USB stick, no manual steps. Repeatable, inventory-driven.

---

## The lab

```
   production-net (NAT, no DHCP)        staging-net (isolated)
   10.10.122.0/24                       10.10.0.0/24
   ┌──────────────┐                     ┌──────────────┐
   │  staging     │  eth0 ─────┐   ┌──── eth1          │
   │  server      │   .2       │   │    .2             │
   │  (control    │            │   │                   │
   │   node)      │            │   │                   │
   └──────┬───────┘            │   │                   │
          │  eth0/eth1  static │   │                   │
          └────────────────────┴───┘                   │
                                                        │
   ┌──────────────┐              ┌─────────────────────┘
   │  EGSE PC     │              │
   │  10.10.122.21 (after)  ◄───┘ 10.10.0.11 (during)
   └──────────────┘   one NIC, re-cabled at handover
```

---

## Mental model

| Real world | The demo |
|---|---|
| Freshly delivered industrial PC | a bare **VM** |
| The bench that preps PCs | the **staging server** VM |
| Factory/bench network | **staging-net** (isolated) |
| Plant production network | **production-net** (NAT) |
| Shipping the PC | re-cabling its **one NIC** at handover |

Everything runs on one laptop — the vocabulary is the real-world analogy.

---

## The lifecycle

1. **Stage** — a bare PC appears (empty disk, PXE boot)
2. **Install** — OS installed over the network, unattended
3. **Configure** — target configuration applied
4. **Verify** — the end state is asserted

Let's watch it happen.

---

<!-- header: Stage -->

## 1 · Stage — the bare PC

A VM as it would arrive from the factory:

- **Empty disk** — no OS
- **One NIC** — on the isolated staging network
- BIOS firmware, deliberately simple hardware
  (e1000 NIC + IDE disk → tiny installer)

Booting from the network = asking to be installed.

---

<!-- header: Install -->

## 2 · Install — PXE + dnsmasq

The PC boots; on the staging network, **dnsmasq** answers:

- DHCP (one reserved address per PC, from the inventory)
- TFTP + PXE → hands it the **deploy kernel + initramfs**

That tiny thing **is** the installer.

---

## 2 · Install — the deploy tool

A ~30-line busybox initramfs (pinned Ubuntu kernel + static busybox):

1. Load the NIC driver
2. Get an address (DHCP)
3. **Download the golden image over HTTP**
4. **Write it to the disk**
5. Power off

The installer is a disposable tool — it is not installed on the PC.

---

## 2 · Install — the golden image

A pre-baked OS "recipe":

- Stock Ubuntu + the lab user and ssh key
- **No packages** — everything else happens in the phase that needs the network
- Built once, reused for every PC

Deterministic, offline-safe to bake.

---

<!-- header: Configure -->

## 3 · Configure — factory phase

On the staging network, **Ansible** (running on the staging server) applies the
factory configuration:

- hostname
- regenerate ssh host keys (no factory keys on the PC)
- write the production netplan — **not applied yet**

The PC is prepared for its real location before it ships.

---

## 3 · Handover — shipping

The PC's **single NIC is re-cabled** from staging to production:

- same machine, same NIC, same identity
- reboots onto its **static production address**

This is why the PC has one port and the networks don't overlap.

---

## 3 · Configure — production phase

On the production network the PC finally gets its workload:

- package repositories
- **OS updates**
- the **EGSE software stack** (git, curl, htop, python3-requests)

Then it's verified — the playbook **asserts**, it doesn't hope.

---

## 4 · Verify — the end state

```
hostname  = egse-pc-01
address   = 10.10.122.21 (expected 10.10.122.21)
netplan   = ok
ssh keys  = regenerated
packages  = git, curl, htop, python3-requests
updates   = up to date
```

Bare machine → configured, verified machine. No manual steps.

(Repeated for **every PC in the run's scope** — one by default, set
`egse_pc_scope` to `all` (or `[egse_pc-02]`) for more — each with its own MAC,
addresses, and hostname from `inventory/host_vars/`.)

---

<!-- header: Offline -->

## Offline fallback

Only the **demo** has an offline mode; setup stays online.

- Online `setup.sh` **bundles** the PC's software into a small apt repo served by the staging server
- Cut the network, run `demo.sh` → it prints **`Mode: offline`**
- The PC installs its software from the bundled repo, not the Ubuntu archive

The offline scenario is a ready-made backup — no mode flag.

---

<!-- header: Key concepts -->

## Key concepts

- **Control node that never moves** — the staging server bridges both networks
- **Config over flags** — everything (IPs, MACs, sizes, pacing, which PCs are
  staged via `egse_pc_scope`) lives in the Ansible inventory; no CLI flags →
  reproducible runs
- **Idempotent** — setup/teardown re-runnable from a clean state
- **Teaching material** — every script is documented to explain its concept

---

## Baseline example

This is a **demo**, not a production system — but it's the engineering pattern:

- golden image + network install
- two-phase configuration
- inventory-driven repeatability
- verification as part of the flow

A real deployment would harden: package signing/GPG, authentication,
monitoring, network isolation, hardware selection.

---

## Thank you

**Questions?**

- `docs/presentation.md` — the presenter's script
- `README.md` — the full technical detail