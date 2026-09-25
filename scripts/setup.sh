#!/usr/bin/env bash
# Bring the whole lab up: golden image (if needed), networks + staging server,
# sync the repo to the staging server, and configure the staging server with
# Ansible.
#
# Core demo concept: setup is OFFLINE-FIRST. It probes the network; when a
# stable network exists it fetches-and-caches everything, when not it falls
# back to lab/cache/ automatically (see lib/common.sh). Re-running setup is
# safe: every step is idempotent.

set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_HOST="$(labvar staging-server mgmt_ip)"
SSH_KEY="$LAB_DIR/keys/egse-demo"

ssh_opts() {
  echo "-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
}

main() {
  require_commands ansible-playbook ansible-inventory python3 rsync ssh

  local mode
  mode="$(detect_mode)"
  echo "Mode: $mode"

  if [ "$mode" = offline ]; then
    require_cache
    echo "Offline mode: running from lab/cache/ only."
  fi

  # 1. Golden image (Task 4). Built when the script exists; otherwise skipped.
  if [ -x "$SCRIPT_DIR/generate_golden_image.sh" ]; then
    echo "Building the golden image ..."
    "$SCRIPT_DIR/generate_golden_image.sh"
  else
    echo "NOTE: scripts/generate_golden_image.sh not present yet; skipping."
  fi

  # 1b. Offline backup (Task 6): bundle the PC's EGSE packages into a small
  #     apt repo so the DEMO can run without a network. Setup itself stays
  #     online-only; this just primes the offline repo.
  if [ "$mode" = online ] && [ -x "$SCRIPT_DIR/fetch_dependencies.sh" ]; then
    "$SCRIPT_DIR/fetch_dependencies.sh"
  elif [ ! -x "$SCRIPT_DIR/fetch_dependencies.sh" ]; then
    echo "NOTE: scripts/fetch_dependencies.sh not present yet; skipping."
  fi

  # 2. Networks + staging server VM.
  "$SCRIPT_DIR/setup_virtuallab.sh"

  # 3. Sync the repo (inventory, playbooks, ssh key, golden image, deploy
  #    assets) to the staging server so it can act as the Ansible control node
  #    for the PCs. --sparse keeps the (mostly-zero) golden image sparse on the
  #    staging server's small disk; lab/cache is host-side only and would just
  #    bloat it (the deploy assets are already extracted into lab/deploy/).
  ensure_ssh_key
  echo "Syncing repo to the staging server ..."
  ssh $(ssh_opts) "ops@$STAGING_HOST" \
    "sudo mkdir -p /srv/egse-demo && sudo chown ops:ops /srv/egse-demo"
  rsync -a --sparse -e "ssh $(ssh_opts)" \
    --exclude '.git' \
    --exclude 'lab/cache' --exclude 'lab/deploy-src' --exclude 'lab/initramfs' \
    --exclude 'lab/*.qcow2' --exclude 'lab/*.iso' --exclude 'lab/seed' \
    "$REPO_ROOT/" "ops@$STAGING_HOST:/srv/egse-demo/"

  # 4. Configure the staging server (installs dnsmasq, pxelinux, ansible, ...).
  #    Online: packages come from the Ubuntu archive. Offline: needs the
  #    bundled apt repo (Milestone 3); until then this step needs the network.
  echo "Configuring the staging server with Ansible ..."
  cd "$REPO_ROOT"
  ansible-playbook ansible/playbooks/staging.yml

  echo "Lab setup complete. Staging server is ops@$STAGING_HOST."
}

main "$@"