# AGENTS.md

Instructions and desired workflows for OpenCode sessions working in this repo.

## Project in one sentence

Virtual lab demo that stages, installs, and configures an industrial PC —
represented as a virtual machine — fully automatically, from scratch.

## Current state (always verify)

- Milestone 1 (project definition) done. Milestone 2 (implementation) in progress:
  repo layout, Ansible inventory, and role/playbook **scaffolds** exist; scripts and
  the live demo do not yet.
- Check `ROADMAP.md` before writing code; mark the relevant task `[~]` while working
  and `[x]` when done.

## Key files

- `README.md` — project documentation. Keep in sync with the actual demo.
- `ROADMAP.md` — the tracker. Update it whenever work starts or finishes.
- `inventory/` — Ansible inventory: the **single source of truth** for machine identity
  (MAC, staging/production IP, hostname) **and VM config** (sizing, networks,
  addresses, behavior flags like `open_terminal_on_setup` in `group_vars/all.yml`).
  The bash scripts read it via `labvar()` in `scripts/lib/common.sh`; per-PC data in
  `inventory/host_vars/`.
- `ansible/` — playbooks and roles (staging server + PC). PC playbooks pick the active
  address (`staging_ip` vs `production_ip`) based on which network the PC is on.
- `scripts/` — demo lifecycle scripts (setup/teardown/generate/fetch/demo).
- `lab/` — gitignored runtime artifacts (VM disks, golden image, cache, ssh keys).

## Workflow conventions

1. Read `ROADMAP.md` first. Confirm the relevant task is `[ ]`/`[~]` before starting;
   mark it `[~]` while working and `[x]` when done.
2. This is a **demo**, not production software. Favor simple, readable, well-commented
   scripts over clever abstractions. The scripts are teaching material.
3. Every demo script must be clearly documented and explain the core demo concept it
   demonstrates — an audience is expected to read them.
4. Keep setup/teardown **idempotent**: re-running setup from a clean state must work.
5. Update `README.md` (demo flow, layout, requirements, getting started) when the
   implementation changes it.
6. The VM **stands in for an industrial PC** — script names, docs, and output should
   reflect the real-world analogy (stage → install → configure → verify), not generic
   "VM provisioning" language, so the demo stays coherent.
7. **Config over flags**: demo behavior is config-driven via the inventory
   (`group_vars/all.yml`), never via command-line flags, so runs are reproducible.
   Flags only on administrative tools (e.g. `install_prereqs.sh --uninstall`).

## Definition of done

- Code works from a clean environment via documented setup steps.
- ROADMAP tasks updated.
- README matches reality.

## Git workflow

- The user stages changes themselves while reviewing. **Never run `git add`** unless
  explicitly asked.
- **Only commit and push on explicit request.** Do not commit or push proactively.
- **What counts as explicit:** the user must say "commit", "commit and push", or
  otherwise clearly authorize it *in response to a direct question about committing*.
  Approval of a plan, task, or deliverable — including a plan whose text mentions
  committing — is **not** authorization to commit. When in doubt, ask.
- **Ask before every commit:** end work with "want me to commit and push?" and wait
  for an explicit yes. Do not rely on a prior "yes" as blanket permission for later
  commits.
- When asked to commit:
  1. Inspect `git status` and `git diff --staged` to see exactly what is staged.
  2. If the staged changes span multiple unrelated concerns, say so and suggest
     splitting them into separate commits; do not bundle unrelated changes.
  3. Propose a commit message (short, imperative, e.g. `Add demo setup script`) and
     use it once approved.
- Push only when explicitly requested, and only to the intended branch.