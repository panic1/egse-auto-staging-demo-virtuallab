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

Make the whole lab runnable without a network: after one online run, both
`setup.sh` (staging server provisioning) and the demo's software install on the
PC work with no internet, using a bundled apt repo.

**Acceptance criteria**

- `fetch_dependencies.sh` bundles the EGSE PC's package set **and the staging
  server's own package set** (plus dependencies) into a small apt repo
  (`lab/apt-repo/`) with a `Packages.gz` index and a `SHA256SUMS` manifest;
  `setup.sh` primes it automatically when online.
- `setup.sh` and `demo.sh` auto-detect the network (`scripts/lib/common.sh`):
  online → the Ubuntu archive; offline → the bundled apt repo and nothing else.
- Running setup once while online primes the repo, so setup and the demo both
  work with no network afterwards.
- Offline: no outbound internet on the host, the staging server, or the PC.
  `setup.sh` recreates the staging server from the cached cloud image, reuses
  the cached golden image/deploy assets (no rebuild), and installs the staging
  server's packages from the bundled repo; the PC installs its stack from the
  same repo (served over HTTP). Nothing is fetched from the internet.
- `README.md` documents the fallback behavior.

**Tasks:** [Task 6](#task-6-offline-dependency-fetch) ·
[Task 7](#task-7-offline-fallback) ·
[Task 12](#task-12-offline-setup)

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
- `teardown.sh` removes the cache, keys, golden image, deploy assets, and offline
  apt repo **when `teardown_clean` is true** — config-driven, no `--clean` flag.
  The default is `false` (keep them), so the offline assets survive teardown (the
  travel workflow); set `teardown_clean: true` for a clean slate.
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
  **Superseded by [Task 12](#task-12-offline-setup):** setup now also runs
  offline, installing its own packages from the same bundled repo; the bundle
  was extended with `staging_packages`.
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

**Status:** `[x]`

**Work instructions**

- Provide automatic mode detection in `scripts/lib/common.sh` (probe a stable network,
  bounded by a timeout) and use it in `demo.sh`.
- Serve the bundled apt repo from the staging server (symlink `/srv/http/apt` →
  `/srv/egse-demo/lab/apt-repo`); point the PC's `apt_mirror` at `apt_repo_url` in
  offline mode.
- Offline: no outbound internet on the host, the staging server, or the PC; the bundled
  apt repo is reachable by the PC (production phase). Setup stays online-only.

**Design information**

- `is_online()`/`detect_mode()` were already in `lib/common.sh` (Task 3/4); `demo.sh`
  reads the mode once at startup and drives the PC's apt source from it.
- The PC's `production.yml` writes a flat-repo apt source (`deb [trusted=yes] ... ./`)
  when `apt_offline` is true (passed by `demo.sh` as an extra var), and the normal
  component sources otherwise. The `verify.yml` "nothing upgradable" assertion holds
  because apt only considers packages the (bounded) repo offers.

**Design decisions**

- **Auto-detect, no `--offline` flag**: online uses the network; offline falls back to
  the bundled apt repo automatically. `demo.sh` passes `apt_offline`/`apt_mirror` as
  Ansible extra vars derived from the detected mode — config-driven, not a user flag.
- **Demo-only offline**: setup (golden image bake, staging server provisioning) remains
  online-only; only the PC's production software install is served offline, from the
  staging server (`apt_repo_url`), not the host.

---

### Task 8: Multiple PC staging

**Status:** `[x]`

**Work instructions**

- Generalize the inventory-driven provisioning to N PCs (`egse_pc-01`, `egse_pc-02`, …).
- `demo.sh` loops over the PCs; verify each PC's end state.

**Design information**

- Most of the N-PC machinery was already inventory-driven: `list_pcs()`
  (scripts/lib/common.sh) enumerates hosts by `egse_pc_name_prefix`, the dnsmasq
  reservation template loops `groups['egse_pcs']`, the PC playbooks target
  `hosts: egse_pcs` with a per-host `ansible_host` derived from each PC's own
  `staging_ip`/`production_ip`, teardown globs `egse_pc-*`, and VM/disk names are
  the PC's inventory key. The only real gap was `demo.sh`'s playbook invocation
  running against the whole `egse_pcs` group.
- The demo stages PCs **sequentially**: for each PC in the scope the full
  four-stage flow runs (stage → install → factory config → handover → production
  config + verify). The inventory defines **two PCs** (`egse_pc-01`,
  `egse_pc-02`, both in `hosts.yml` with identities in their `host_vars/`
  files); `egse_pc_scope` in `group_vars/all.yml` defaults to `[egse_pc-01]`.
  Because both PCs are in the inventory, `setup.sh` primes dnsmasq with **both**
  DHCP reservations in one run — staging a second PC later needs no re-setup,
  only a scope change. Adding further PCs is a new host entry in `hosts.yml`
  plus a matching `host_vars/egse_pc-0N.yml` (MAC, hostname, staging_ip,
  production_ip) — nothing else.

**Design decisions**

- **No `--only` flag.** PC selection is config, not a flag: `egse_pc_scope` in
  `group_vars/all.yml` names the PCs a `demo.sh` run stages (`[egse_pc-01]` by
  default, `all` for every PC, or a list). The original `--only egse_pc-0X`
  clause was dropped (config-over-flags, AGENTS.md).
- **Playbooks are scoped by network state, per run.** `run_pc_playbook` passes
  `--limit "$pc"`: during the sequential demo exactly one PC is on the relevant
  network at a time (staging playbook → the PC on the staging net; production
  playbook → the just-handed-over PC). Because the playbooks target
  `hosts: egse_pcs` with per-host `ansible_host`, an ad-hoc run without a limit
  still updates all PCs already on the production network.
- **A single golden image is reused for all PCs**; identity differs via the
  inventory (MAC, staging/production IP, hostname).
- **`fetch_dependencies.sh` reads the group-level `egse_pc_packages` from the
  first listed PC** (via `list_pcs`) instead of hardcoding `egse_pc-01`, so the
  offline bundle no longer breaks if that specific host is renamed/removed.
- **`demo.sh` stages a config-driven subset (`egse_pc_scope`)** rather than
  always every PC: `[egse_pc-01]` (default) stages one PC, `all` stages the
  whole inventory, or a list like `[egse_pc-02]` stages only those. This lets a
  presenter add a PC to an already running lab (e.g. stage `egse_pc-02` while
  `egse_pc-01` keeps running on the production network) without a `--only` flag
  and without re-running `setup.sh` — both PCs are in the inventory, so their
  dnsmasq reservations are primed by the initial setup. Scope by config, not by
  flag. A scoped host not in the inventory is a clear error, not a silent no-op.
  (Real-world note: production PCs aren't disposable VMs — the scope exists so a
  live, already-staged PC is never wiped by a re-run of the demo.)

---

### Task 9: Rehearse demo

**Status:** `[x]`

**Work instructions**

- Run the full demo from a clean environment and fix any gaps.

**Design information**

- Rehearsal run from a clean state (teardown → setup from cache → demo) with
  `egse_pc_scope: [egse_pc-01]` and `demo_pause: false`:
  - `teardown.sh` ≈ **0.1 min** (with `teardown_clean: false` keeping cache).
  - `setup.sh` ≈ **2.7 min** (rebuilt the staging server from cache; no
    re-download of the cloud image or deploy assets).
  - `demo.sh` ≈ **4.3 min** — the full one-PC flow
    (stage → install → factory → handover → production → verify) completed
    cleanly with no pauses, no terminal windows, and the verification summary
    printed. No gaps found.
- Config was restored to defaults afterwards (`demo_pause: true`,
  `open_terminal_on_demo: true`, `teardown_clean: false`).

**Design decisions**

- Rehearsal used the default single-PC scope and no pause (unattended run) —
  every stage of the flow is exercised either way, at roughly half the runtime
  of a two-PC run.

---

### Task 10: Prepare presentation materials

**Status:** `[x]`

**Work instructions**

- Prepare slides / talking points that explain the core concepts.

**Design information**

- `docs/presentation.md` is a **presenter's guide**, not a slide deck: a
  phase-by-phase script that mirrors the actual `demo.sh` output (`==> 1/4 STAGE`,
  `2/4 INSTALL`, `3/4 CONFIGURE`, `3/4 HANDOVER`, `4/4 CONFIGURE + VERIFY`), so
  the presenter talks in lockstep with the running demo. It covers the opening
  pitch, the mental model (real world ↔ VM mapping), a preparation checklist, the
  offline variant, and likely Q&A.
- `docs/slides.md` is the **slide deck** (Marp markdown: `---` per slide, front
  matter `marp: true`), ~21 slides sized for a 15–30 min talk. Rendered with the
  Marp CLI (`npx @marp-team/marp-cli docs/slides.md [--pdf]`) or the Marp for
  VS Code extension.

**Design decisions**

- **Talking points over slides.** The demo is the visual; the guide gives the
  words and the concepts per phase. It can be turned into slides later without
  losing content. (This materialized as two files: `slides.md` for the visuals,
  `presentation.md` for the script.)
- **Tied to the real script output** so rehearsal and delivery stay consistent
  with what the audience sees on screen.
- **Marp markdown** (plain markdown + `---` breaks) chosen over reveal.js/HTML:
  versionable, readable in the repo, and renders to HTML/PDF with a free tool on
  the presenter's machine.

---

### Task 11: Deliver demo

**Status:** `[ ]`

**Work instructions**

- Present the demo to the audience.
- Do a **dress rehearsal** first: a narrated, paused run (as the audience will
  see it) against `docs/presentation.md`'s phase-by-phase script, with
  `demo_pause: true` and `open_terminal_on_demo: true`. Unlike the Task 9
  technical rehearsal (unattended), this mirrors the real show.
- **Study the slide deck** (`docs/slides.md`) and presenter's script
  (`docs/presentation.md`) until the mapping deck ↔ words ↔ live output is
  second nature.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 12: Offline setup

**Status:** `[x]`

**Work instructions**

- Bundle the staging server's own package set (`staging_packages`) into the
  offline apt repo alongside the PC's, so `setup.sh` can provision the staging
  server with no network.
- Give the `staging_server` role an offline install path: point apt at the
  bundled flat repo and drop the archive sources before installing.
- `setup.sh` passes the detected mode explicitly to `staging.yml` (one shared
  `apt_offline` value), so an inventory default can't decide it; the
  golden/deploy bake self-skips when the cached assets are present.

**Design information**

- **Why:** the demo travel plan is online `setup.sh` + `teardown.sh`
  (`teardown_clean: false`) at home, then offline `setup.sh` + `demo.sh` at the
  meeting. Teardown destroys the staging server VM, so the meeting setup must
  recreate it from the cached cloud image and install its five packages with no
  network. Previously only the PC's packages were bundled, so the "install
  staging server packages" task failed offline.
- **Three installs** across the trip: (1) home setup provisions the staging
  server online; (2) meeting setup provisions the staging server offline from
  the bundle; (3) meeting demo provisions the PC offline from the bundle. Runs
  (2) and (3) reuse the cached cloud image, golden image, deploy assets, and
  apt repo — nothing is rebuilt or fetched.
- `staging_packages` lives in `inventory/group_vars/staging.yml` (single source
  of truth), read by both the role and `fetch_dependencies.sh`.

**Design decisions**

- **One shared `apt_offline` value, not a staging-specific flag.** Each run
  provisions exactly one machine, and each script knows the network state at
  that moment, so `setup.sh` and `demo.sh` each pass the mode explicitly.
  `ansible-playbook staging.yml` run manually falls back to the inventory value.
- **Mechanism: rewrite the staging server's apt sources** (`deb [trusted=yes]
  file:<repo> ./`, remove `ubuntu.sources`) rather than a one-off apt option.
  This mirrors the PC's `production.yml`, so the "use the bundle when offline"
  idea is taught once and reused; the staging server is disposable, so the
  rewrite needs no restore.
- **Offline setup requires a primed bundle.** If `lab/apt-repo` is missing, the
  role fails with clear guidance instead of a confusing apt error.
- **Known minor issue (deferred):** `setup.sh` used to print "Building the
  golden image ..." before calling the idempotent bake, which read like a
  rebuild even when it skipped; the message is now neutral.