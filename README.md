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

### Requirements

(TBD — host hypervisor, tooling, and VM prerequisites.)

### Milestones

See [ROADMAP.md](./ROADMAP.md) for the project tracker with milestones and tasks.