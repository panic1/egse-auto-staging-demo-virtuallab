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
  (MAC, staging/production IP, hostname). Per-PC data in `inventory/host_vars/`.
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

## Definition of done

- Code works from a clean environment via documented setup steps.
- ROADMAP tasks updated.
- README matches reality.

## Git workflow

- The user stages changes themselves while reviewing. **Never run `git add`** unless
  explicitly asked.
- **Only commit and push on explicit request.** Do not commit or push proactively.
- When asked to commit:
  1. Inspect `git status` and `git diff --staged` to see exactly what is staged.
  2. If the staged changes span multiple unrelated concerns, say so and suggest
     splitting them into separate commits; do not bundle unrelated changes.
  3. Propose a commit message (short, imperative, e.g. `Add demo setup script`) and
     use it once approved.
- Push only when explicitly requested, and only to the intended branch.