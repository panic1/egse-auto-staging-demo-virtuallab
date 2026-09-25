# ROADMAP

Project tracker for the EGSE auto-staging demo virtual lab. This file is the source
of truth for what remains to be done.

Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

The tracker has two chapters:

- **Milestones** — the goals, each with a description, acceptance criteria, and links
  to the tasks that deliver it.
- **Tasks** — the concrete units of work, each with work instructions, detailed design
  information, and design decision records.

---

## Milestones

### Milestone 1 — Project Definition

Establish the project's purpose and working agreements in writing. No code yet.

**Acceptance criteria**

- `README.md`, `ROADMAP.md`, and `AGENTS.md` exist and reflect the agreed structure.
- `AGENTS.md` reviewed and approved by the user.
- No implementation code committed.

**Tasks:** [Task 1](#task-1-establish-project-definition-documents)

---

### Milestone 2 — Implementation

Deliver a runnable demo that stages, installs, and configures a VM standing in for an
industrial PC, from scratch, with a staging server.

**Acceptance criteria**

- Setup from a clean state produces a bare PC VM representing a freshly delivered
  industrial PC.
- The staging server (a separate VM) PXE-boots the PC over an isolated staging network
  and installs a golden image onto it.
- The PC is initially configured on the staging network, then re-cabled to the
  production network where it receives its software and updates.
- Teardown destroys the VMs and cleans up demo artifacts. Setup is idempotent.
- Every demo script is documented and explains the core concept it demonstrates.
- `README.md` updated to match reality (demo flow, layout, requirements, getting
  started).

**Tasks:** [Task 2](#task-2-define-demo-environment) ·
[Task 3](#task-3-setup-and-teardown-scripts) ·
[Task 4](#task-4-demo-scripts) ·
[Task 5](#task-5-update-readme-for-implementation)

---

### Milestone 3 — Offline Fallback

Make the demo runnable without a network: setup stays online, but after one
online run the demo's software install on the PC works with no internet, using
a bundled apt repo.

**Acceptance criteria**

- `fetch_dependencies.sh` bundles the EGSE PC's package set and dependencies
  into a small apt repo (`lab/apt-repo/`) with a `Packages.gz` index and a
  `SHA256SUMS` manifest; `setup.sh` primes it automatically when online.
- `demo.sh` auto-detects the network (`scripts/lib/common.sh`): online → the PC
  uses the Ubuntu archive; offline → the bundled apt repo and nothing else.
- Running setup once while online primes the repo, so the demo works with no
  network afterwards.
- Offline: no outbound internet on the host, the staging server, or the PC; the
  bundled apt repo is reachable by the PC (production phase). Setup remains
  online-only.
- `README.md` documents the fallback behavior.

**Tasks:** [Task 6](#task-6-offline-dependency-fetch) ·
[Task 7](#task-7-offline-fallback)

---

### Milestone 4 — Multiple PC Staging

Stage several PCs from one inventory-driven run, demonstrating repeatability.

**Acceptance criteria**

- 2+ PCs (`egse_pc-01`, `egse_pc-02`, …) each with their own MAC, staging IP, production IP, and
  hostname in the inventory.
- dnsmasq reservations, Ansible, and `demo.sh` scale from the inventory with no code
  duplication.
- `demo.sh` stages all PCs (or a selected one) through the full flow; verify asserts
  each PC's end state.

**Tasks:** [Task 8](#task-8-multiple-pc-staging)

---

### Milestone 5 — Demo Presentation

Present the working demo to an audience.

**Acceptance criteria**

- The full demo runs successfully from a clean environment during rehearsal.
- Presentation materials / talking points are ready.
- The demo is delivered.

**Tasks:** [Task 9](#task-9-rehearse-demo) ·
[Task 10](#task-10-prepare-presentation-materials) ·
[Task 11](#task-11-deliver-demo)

---

## Tasks

### Task 1: Establish project definition documents

**Status:** `[x]`

**Work instructions**

- Draft `README.md` (project documentation), `ROADMAP.md` (tracker), and `AGENTS.md`
  (agent instructions and workflows).
- Get `AGENTS.md` reviewed and approved by the user.
- Confirm demo scope and target audience with stakeholders.

**Design information**

- No code in this phase; documents only.

**Design decisions**

- The tracker is split into **Milestones** and **Tasks** chapters: milestones carry
  goals and acceptance criteria; tasks carry the how and the decisions.
- The VM is treated as a stand-in for an industrial PC, and all naming/docs use that
  analogy (see `AGENTS.md`).

---

### Task 2: Define demo environment

**Status:** `[x]`

**Work instructions**

- Confirm the VM toolchain (libvirt/KVM + shell scripts; no Vagrant).
- Define the networks: `staging-net` (isolated) and the production network (host NAT).
- Define the VMs: staging server and PC(s), their disks, NICs, firmware, and addresses.
- Document host prerequisites (Ubuntu 24.04, KVM packages, libguestfs).

**Design information**

- Host: Ubuntu 24.04 with KVM/libvirt. Everything runs in the system daemon
  (`qemu:///system` — the session daemon cannot create the bridge networks the demo
  needs): the NAT `production-net` network and the isolated `staging-net` are both defined
  there by the scripts. VM disks and seed ISOs are created as volumes in libvirt's
  `default` storage pool, so `libvirt-qemu` can access them without touching this
  repo's permissions.
- Staging server: Ubuntu 24.04 cloud image, two NICs. PC: empty disk, e1000 NIC, IDE
  disk, BIOS firmware, PXE boot (network then disk).
- Golden image built with libguestfs (`virt-customize`); deployed by a tiny busybox
  initramfs that downloads the image over HTTP and writes it to disk.
- Boot files + golden image + apt repo are served by the staging server over HTTP/TFTP.
- Ansible inventory is the single source of truth for PC identity.

**Design decisions**

- **Staging and production use non-overlapping ranges** (`10.10.0.0/24` vs
  `10.10.122.0/24`): the staging server bridges both networks, so overlapping ranges
  would confuse its routing. The production range deliberately avoids
  `192.168.122.0/24` (the system daemon's `virbr0`/`default` network owns that on many
  hosts).
- **The staging server gets a static production-side address** (`10.10.122.2`) so it
  is a stable target for Ansible and the apt repo.
- **The production network has NO DHCP** — every device on it is pinned to a static
  address (staging server eth0, and each PC after handover). DHCP exists only on the
  isolated staging network, served by dnsmasq for the PXE install.
- **The PC has a single network port**, re-cabled from `staging-net` to the host network
  at handover, simulating the PC shipping to its production location. It is configured
  in two phases (factory config on the staging net, then software/updates on the
  production net).
- **Golden-image deployment, BIOS firmware, e1000 NIC + IDE disk**: the deploy initramfs
  needs no extra kernel modules.
- The staging server is the **Ansible control node** for the PCs (it has a foot in both
  networks), so the control node never changes through the handover.
- Scaled to multiple PCs purely from the inventory (Milestone 4); no per-PC code.

---

### Task 3: Setup and teardown scripts

**Status:** `[x]`

**Work instructions**

- `setup_virtuallab.sh` — define `staging-net`, create + boot the staging server VM.
- `setup.sh` — generate the golden image if needed, run `setup_virtuallab.sh`, sync the
  repo to the staging server, run the `staging.yml` playbook.
- `teardown.sh` — destroy the VMs and network, remove demo artifacts; keep the golden
  image unless `--clean`. Idempotent.

**Design information**

- `staging-net`: an isolated libvirt network (`<forward mode='none'/>`), deliberately
  L2-only — the host has no address on it, so PCs are only reachable via the staging
  server.
- Staging server: Ubuntu 24.04 cloud image (cached, offline-first), copied + resized to
  10G (cloud-init `growpart` expands the root). A NoCloud seed provides the `ops`
  user, the shared ssh key, and a static netplan: eth0 = `10.10.122.2` on the
  production network, eth1 = `10.10.0.2` on `staging-net`. Sized small (1 vCPU, 1 GiB
  RAM) — the demo needs no performance.
- `setup.sh`: detect mode → golden image (if the script exists) → `setup_virtuallab.sh`
  → rsync the repo to `/srv/egse-demo` on the staging server → run `staging.yml`.
- `teardown.sh`: destroys the staging server and any `egse_pc-*` domains plus
  `staging-net`; keeps cache/keys/golden image unless `--clean`.

**Design decisions**

- **Fixed MACs + static addresses via cloud-init network-config** for both staging
  server NICs — no dependency on libvirt DHCP reservations.
- **The staging network carries no host address** (pure L2): the PCs cannot be reached
  from the host at all, only via the staging server.
- The repo is **rsynced to the staging server** (`/srv/egse-demo`) so it is the Ansible
  control node for the PCs; VM disks and ISOs are excluded.
- `teardown.sh` removes the cache, keys, and golden image **when `teardown_clean` is
  true (default)** — config-driven, no `--clean` flag. Set `teardown_clean: false` to
  keep them (e.g. so the offline backup stays primed across repeated teardowns).
- **Config-over-flags**: demo behavior is driven by the inventory config, never by
  command-line flags, so every run is reproducible. Flags remain only on
  administrative tools (`install_prereqs.sh --uninstall/--help`). `demo.sh` follows
  the same rule.
- `install_prereqs.sh` **tracks what it changes** (`lab/install_prereqs.state`: packages
  actually installed, groups actually added) so `--uninstall` undoes exactly that and
  never removes software that was already on the machine.
- **The lab user is `ops`**: the name must not match any group on the image, because
  cloud-init's `useradd` fails when the same-named group already exists (`USERGROUPS_ENAB
  yes`). `admin` (gid 110) and `operator` (gid 37) both collide; `ops` matches no group.
  This applies to the golden image / PC user too (Task 4).
- **All VM config lives in the Ansible inventory** (group_vars/all.yml + staging.yml +
  egse_pcs.yml): sizes, MACs, addresses, network names, os-variant, NIC model. The
  scripts read it via `labvar()` in `common.sh` (`ansible-inventory --host ...`), so the
  inventory stays the single source of truth and nothing is hardcoded in the scripts.

---

### Task 4: Demo scripts

**Status:** `[x]`

**Work instructions**

- `generate_golden_image.sh` — bake the golden image (Ubuntu 24.04 minimal + ssh +
  lab user) and build the busybox deploy initramfs.
- `demo.sh` — create the bare PC VM, run the install/configure/handover/verify flow with
  concise logged steps and pauses, and open show-and-tell terminals into the VMs.
- Document each script so it explains the core demo concept it demonstrates.

**Design information**

- PXE flow: dnsmasq (DHCP + TFTP + PXE on the staging interface) → pxelinux.0 →
  deploy kernel + initramfs → download `golden.img` via HTTP → `dd` to disk → reboot.
- PC boots into the golden OS with DHCP; Ansible (from the staging server) applies the
  factory configuration, then the PC is re-cabled and rebooted, and Ansible applies the
  production configuration.

**Design decisions**

- **The golden image bake installs no packages** (the cloud image already ships
  openssh-server): all tools/libraries are applied via apt in the production phase.
  This keeps the bake fully offline-safe.
- **Small VM sizes throughout** — the demo needs no performance: staging server and EGSE
  PC are 1 vCPU / 1 GiB RAM; the golden image and both VM disks are ~8–10 GB.

**Implementation learnings (Task 4)**

- `virt-resize --expand` breaks the noble cloud image boot (renumbered partitions +
  reinstalled GRUB hang). The bake keeps the cloud image's partition layout/GRUB
  unchanged and accepts its ~2.7G root; production disk hygiene (`apt autoremove`/clean)
  keeps it from filling up.
- cloud-init's first-boot ssh host key generation is skipped once cloud-init is disabled,
  so the golden image bakes the keys with `ssh-keygen -A` — without them sshd won't start.
- The PC's NIC is named `eth0`/`ens3` (interface names differ between the deploy tool and
  the OS); netplan matches it by **driver** (`e1000`), since `match.name` is a single glob
  and no one glob covers both naming schemes.
- `systemd-networkd-wait-online` is disabled in the golden image so a slow/absent network
  never stalls the boot at the splash.
- Ansible `tasks_from` is an `import_role` parameter — the `roles:` list keyword ignores
  it (a subtle gotcha that made both role phases run).
- Hostnames allow no underscores: the PC's Linux hostname is `egse-pc-01` while its
  inventory key / VM name stays `egse_pc-01`.

---

### Task 5: Update README for implementation

**Status:** `[x]`

**Work instructions**

- Fill in demo flow, layout, requirements, and getting started to match the actual
  implementation.

**Design information**

- The README is split into a narrative part (Overview, Core Concepts, Demo Flow,
  Getting Started) and a Reference part (Layout, Requirements & Assumptions,
  Milestones). The Demo Flow and Layout sections were filled during Task 4, at the
  user's request, since the implementation existed by then; Task 5 completed the
  Getting Started section and aligned the requirements/assumptions with the actual
  implementation.

**Design decisions**

- **Getting Started is a short, ordered command walk-through** (install prereqs →
  setup → demo → teardown) plus a pointer to the inventory for the behavior knobs
  (`demo_pause`, `open_terminal_on_setup`, `open_terminal_on_demo`, `teardown_clean`),
  so a presenter can bring the demo up with no other documentation.
- **The documented host package list is generated from `install_prereqs.sh`** (the
  single source of truth for host prerequisites), not maintained separately.
- **The offline-fallback wording stays as-is** until Milestone 3 lands; the full
  offline bundle (bundled apt repo) is documented there.

---

### Task 6: Offline dependency fetch

**Status:** `[x]`

**Work instructions**

- `fetch_dependencies.sh`: bundle the EGSE PC's package set (`egse_pc_packages`
  in the inventory) plus all their dependencies into a small flat apt repo at
  `lab/apt-repo/`, with a `Packages.gz` index and a `SHA256SUMS` manifest.
- `setup.sh` calls `fetch_dependencies.sh` when online, so the offline demo is
  primed automatically.

**Design information**

- `lab/apt-repo/` is gitignored (under `lab/`). The staging server serves it to
  the PC at `apt_repo_url` (`http://10.10.122.2/apt`) in offline mode.

**Design decisions**

- **Only the demo has an offline mode; setup stays online-only.** Setup fetches
  the cloud image, build assets, and provisions the staging server over the
  network. The single offline deliverable is the bundled apt repo for the PC's
  production phase. The original "boot-asset cache + manifest" scope (cloud
  image, syslinux/pxelinux, busybox, deploy kernel) was dropped accordingly —
  those are all fetched at online setup.
- **Bundled apt repo** (explicit `.deb` set + `dpkg-scanpackages`) chosen over
  `apt-cacher-ng` or baking everything into the image: deterministic, small,
  and easy to explain in the demo. Flat repo + `[trusted=yes]` (no GPG).
- **Bounded package set**: `egse_pc_packages` + full dependency closure
  (no Recommends/Suggests). The PC's offline `apt upgrade` only upgrades what
  the repo contains, so "nothing upgradable" in the verify still holds.
- The repo is served from the staging server (not the host) — the PC reaches it
  at `apt_repo_url`; the staging server's own provisioning stays online.

---

### Task 7: Offline fallback

**Status:** `[ ]`

**Work instructions**

- Provide automatic mode detection in `scripts/lib/common.sh` (probe a stable network,
  bounded by a timeout) and use it in `demo.sh`.
- Serve the bundled apt repo from the staging server (symlink `/srv/http/apt` →
  `/srv/egse-demo/lab/apt-repo`); point the PC's `apt_mirror` at `apt_repo_url` in
  offline mode.
- Offline: no outbound internet on the host, the staging server, or the PC; the bundled
  apt repo is reachable by the PC (production phase). Setup stays online-only.

**Design information**

- TBD.

**Design decisions**

- **Auto-detect, no `--offline` flag**: online uses the network; offline falls back to
  the bundled apt repo automatically. The offline scenario is a ready-made backup.
- **Demo-only offline**: setup (golden image bake, staging server provisioning) remains
  online-only; only the PC's production software install is served offline, from the
  staging server (`apt_repo_url`), not the host.

---

### Task 8: Multiple PC staging

**Status:** `[ ]`

**Work instructions**

- Generalize the inventory-driven provisioning to N PCs (`egse_pc-01`, `egse_pc-02`, …).
- `demo.sh` loops over the PCs (or `--only egse_pc-0X`); verify each PC's end state.

**Design information**

- TBD.

**Design decisions**

- A single golden image is reused for all PCs; identity differs via the inventory
  (MAC, staging/production IP, hostname).

---

### Task 9: Rehearse demo

**Status:** `[ ]`

**Work instructions**

- Run the full demo from a clean environment and fix any gaps.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 10: Prepare presentation materials

**Status:** `[ ]`

**Work instructions**

- Prepare slides / talking points that explain the core concepts.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 11: Deliver demo

**Status:** `[ ]`

**Work instructions**

- Present the demo to the audience.

**Design information**

- TBD.

**Design decisions**

- TBD.