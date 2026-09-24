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
industrial PC, from scratch.

**Acceptance criteria**

- Setup from a clean state produces a bare VM representing a freshly staged industrial
  PC.
- Teardown destroys the VM and cleans up demo artifacts.
- Setup is idempotent: re-running from a clean state works without manual cleanup.
- Install, configure, and verify steps run unattended end-to-end.
- Every demo script is documented and explains the core concept it demonstrates.
- `README.md` updated to match reality (demo flow, layout, requirements, getting
  started).

**Tasks:** [Task 2](#task-2-define-demo-environment) ·
[Task 3](#task-3-setup-and-teardown-scripts) ·
[Task 4](#task-4-demo-scripts) ·
[Task 5](#task-5-update-readme-for-implementation)

---

### Milestone 3 — Demo Presentation

Present the working demo to an audience.

**Acceptance criteria**

- The full demo runs successfully from a clean environment during rehearsal.
- Presentation materials / talking points are ready.
- The demo is delivered.

**Tasks:** [Task 6](#task-6-rehearse-demo) ·
[Task 7](#task-7-prepare-presentation-materials) ·
[Task 8](#task-8-deliver-demo)

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

**Status:** `[ ]`

**Work instructions**

- Decide the VM guest spec (OS, resources) representing the industrial PC.
- Document host prerequisites: hypervisor, tooling, disk/network.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 3: Setup and teardown scripts

**Status:** `[ ]`

**Work instructions**

- `setup` — create the bare VM (the "stage" state).
- `teardown` — destroy the VM and clean up demo artifacts.
- Ensure setup is idempotent: safe to re-run from a clean state without manual cleanup.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 4: Demo scripts

**Status:** `[ ]`

**Work instructions**

- Install step — unattended OS / base software install.
- Configure step — apply the target configuration automatically.
- Verify step — assert the VM reached its expected end state.
- Document each script so it explains the core demo concept it demonstrates.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 5: Update README for implementation

**Status:** `[ ]`

**Work instructions**

- Fill in demo flow, layout, requirements, and getting started to match the actual
  implementation.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 6: Rehearse demo

**Status:** `[ ]`

**Work instructions**

- Run the full demo from a clean environment and fix any gaps.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 7: Prepare presentation materials

**Status:** `[ ]`

**Work instructions**

- Prepare slides / talking points that explain the core concepts.

**Design information**

- TBD.

**Design decisions**

- TBD.

---

### Task 8: Deliver demo

**Status:** `[ ]`

**Work instructions**

- Present the demo to the audience.

**Design information**

- TBD.

**Design decisions**

- TBD.