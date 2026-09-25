#!/usr/bin/env bash
# Common helpers for the demo lifecycle scripts in ../.. .
# Source this file from a script:
#   . "$(dirname "$0")/lib/common.sh"
#
# Core demo concept: the demo is OFFLINE-FIRST. Every external asset (Ubuntu
# cloud image, PXE boot files, the .deb bundle) is cached under lab/cache/.
# Each script probes the network: when a stable network is reachable it
# fetches-and-caches; when it is not, it falls back to the cache automatically.
# So the offline scenario is a ready-made backup, not a special mode.

set -euo pipefail

# Repo root and derived paths (this file lives in <repo>/scripts/lib/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_DIR="$REPO_ROOT/lab"
CACHE_DIR="$LAB_DIR/cache"

# Host:port probed to decide whether a stable network exists. A pure-TCP check
# (bash /dev/tcp) is used instead of ping/curl: ICMP is often filtered on lab
# networks, and this needs no curl/wget installed on the host.
ONLINE_PROBE_HOST="${ONLINE_PROBE_HOST:-archive.ubuntu.com}"
ONLINE_PROBE_PORT="${ONLINE_PROBE_PORT:-443}"

# Return 0 (reachable) when a stable network exists, 1 otherwise.
# Bounded by `timeout` so an unreachable host fails fast instead of hanging on
# the kernel's default connect timeout.
is_online() {
  timeout 6 bash -c "exec 3<>/dev/tcp/${ONLINE_PROBE_HOST}/${ONLINE_PROBE_PORT}" 2>/dev/null
}

# Print the detected mode: "online" or "offline".
detect_mode() {
  if is_online; then
    echo online
  else
    echo offline
  fi
}

# Abort with guidance when the cache is missing but needed (offline).
require_cache() {
  if [ ! -d "$CACHE_DIR" ] || [ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]; then
    echo "ERROR: network unavailable and lab/cache/ is empty." >&2
    echo "  Run ./scripts/fetch_dependencies.sh once on a connected machine" >&2
    echo "  so the demo can fall back to offline mode." >&2
    exit 1
  fi
}

# Require that every named command exists; print install guidance and exit if not.
require_commands() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: missing required tools on the host: ${missing[*]}" >&2
    echo "  On Ubuntu 24.04 install them with:" >&2
    echo "    sudo apt install qemu-kvm libvirt-daemon-system virtinst libguestfs-tools cloud-image-utils ansible rsync curl" >&2
    exit 1
  fi
}

# Read a variable for a host from the Ansible inventory — the single source of
# truth for machine identity, VM sizing, and network layout. Prints the value,
# or the optional default when it is absent or ansible-inventory is missing.
labvar() {
  local host="$1"
  local var="$2"
  local default="${3:-}"
  local value=""
  if command -v ansible-inventory >/dev/null 2>&1; then
    value="$(ansible-inventory -i "$REPO_ROOT/inventory/hosts.yml" --host "$host" 2>/dev/null \
      | python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$var")"
  fi
  if [ -z "$value" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$value"
  fi
}

# Like labvar, but for LIST-valued variables: prints one element per line.
# A scalar value is printed as-is; an optional default is used when the var is
# absent or ansible-inventory is missing (parity with labvar).
labvar_list() {
  local host="$1"
  local var="$2"
  local default="${3:-}"
  local value=""
  if command -v ansible-inventory >/dev/null 2>&1; then
    value="$(ansible-inventory -i "$REPO_ROOT/inventory/hosts.yml" --host "$host" 2>/dev/null \
      | python3 -c 'import json,sys
d = json.load(sys.stdin)
v = d.get(sys.argv[1], [])
print("\n".join(v) if isinstance(v, list) else v)' "$var")"
  fi
  if [ -z "$value" ]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$value"
  fi
}

# Generate the shared demo ssh keypair (lab/keys/egse-demo) if it is missing.
# The same key authorizes the lab user on the staging server and on every EGSE PC.
ensure_ssh_key() {
  if [ ! -f "$LAB_DIR/keys/egse-demo" ]; then
    mkdir -p "$LAB_DIR/keys"
    ssh-keygen -t ed25519 -N "" -f "$LAB_DIR/keys/egse-demo" >/dev/null
    echo "Generated ssh key pair lab/keys/egse-demo(.pub)."
  fi
}

# Poll until ssh to the given host succeeds. Cloud images need time for first
# boot (growpart, cloud-init), so this retries for a while. An optional jump
# host (`user@host`) routes the connection through the staging server — needed
# because the host has no address on the isolated staging network, so PCs
# there are only reachable via the staging server. A ProxyCommand (not -J) is
# used so the demo ssh key is also offered to the jump host.
wait_for_ssh() {
  local host="$1"
  local user="$2"
  local key="$3"
  local tries="${4:-60}"
  local jump="${5:-}"
  local jump_opts=()
  if [ -n "$jump" ]; then
    local jump_user="${jump%%@*}"
    local jump_host="${jump#*@}"
    jump_opts=(-o "ProxyCommand=ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p $jump_user@$jump_host")
  fi
  echo "Waiting for ssh $user@$host (cloud image first boot can take a while) ..."
  for _ in $(seq 1 "$tries"); do
    if ssh "${jump_opts[@]}" -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 "$user@$host" true 2>/dev/null; then
      echo "SSH ready: $user@$host"
      return 0
    fi
    sleep 5
  done
  echo "ERROR: $user@$host did not become reachable via ssh." >&2
  return 1
}

# Open a separate terminal window running an ssh session into a VM. This is the
# demo's "show-and-tell" window — a live shell into the machine while the demo
# runs. Falls back to printing the command if no terminal emulator is present.
# An optional jump host (`user@host`) is used for machines on the isolated
# staging network (see wait_for_ssh).
open_ssh_terminal() {
  local title="$1"
  local user="$2"
  local host="$3"
  local key="$4"
  local jump="${5:-}"
  local cmd="ssh"
  if [ -n "$jump" ]; then
    local jump_user="${jump%%@*}"
    local jump_host="${jump#*@}"
    cmd="$cmd -o ProxyCommand=\"ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p $jump_user@$jump_host\""
  fi
  cmd="$cmd -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $user@$host"
  # The terminal window is a show-and-tell nicety — a broken/missing terminal
  # emulator must never abort the demo, so failures just fall back to printing
  # the connect command.
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="$title" -- bash -c "$cmd; exec bash" 2>/dev/null \
      || { echo "NOTE: could not open a terminal window — connect manually with:" >&2; echo "  $cmd" >&2; }
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -c "$cmd; exec bash" 2>/dev/null \
      || { echo "NOTE: could not open a terminal window — connect manually with:" >&2; echo "  $cmd" >&2; }
  else
    echo "No terminal emulator found — open this yourself in another terminal:" >&2
    echo "  $cmd" >&2
  fi
}

# Print a numbered/logged step header. Used by demo.sh to narrate the stages.
step() {
  echo
  echo "==> $*"
}

# Demo narration pause. Config-driven (inventory group_vars/all.yml,
# demo_pause) — never a command-line flag, so runs stay reproducible
# (see AGENTS.md "Config over flags").
demo_pause() {
  local label="${1:-}"
  local enabled
  enabled="$(labvar staging-server demo_pause true | tr '[:upper:]' '[:lower:]')"
  if [ "$enabled" = true ]; then
    printf '    [demo] %s — press Enter to continue ...' "$label"
    read -r _
    echo
  fi
}

# List the EGSE PC hostnames (egse_pc-01, ...) from the inventory. The
# inventory is the single source of truth for which PCs the demo stages.
list_pcs() {
  local prefix
  prefix="$(labvar staging-server egse_pc_name_prefix egse_pc-)"
  ansible-inventory -i "$REPO_ROOT/inventory/hosts.yml" --list 2>/dev/null \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
hv=d.get("_meta",{}).get("hostvars",{})
print("\n".join(sorted(h for h in hv if h.startswith(sys.argv[1]))))' "$prefix"
}

# Fetch a URL into the cache unless it is already there. Returns the cached
# path. Fails (with guidance) if offline and the asset is missing.
fetch_or_fallback() {
  local url="$1"
  local out="$CACHE_DIR/$(basename "$url")"

  if [ -f "$out" ]; then
    echo "$out"
    return
  fi

  if is_online; then
    mkdir -p "$CACHE_DIR"
    echo "Downloading $url ..." >&2
    curl -fSL -o "$out" "$url"
    echo "$out"
    return
  fi

  echo "ERROR: '$url' is not cached and the network is unavailable." >&2
  echo "  Run ./scripts/fetch_dependencies.sh on a connected machine." >&2
  exit 1
}

# libvirt connection the demo uses (see group_vars/all.yml, libvirt_uri).
# The system daemon is required because the demo needs bridge networks. VM
# disks and seed ISOs live in the libvirt storage pool so libvirt-qemu can
# access them without touching this repo's permissions.
LIBVIRT_URI="$(labvar staging-server libvirt_uri qemu:///system)"

# Run virsh against the configured libvirt connection.
vsh() {
  virsh -c "$LIBVIRT_URI" "$@"
}