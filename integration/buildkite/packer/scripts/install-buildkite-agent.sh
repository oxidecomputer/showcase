#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
  echo "${0} must run as root" >&2
  exit 1
fi

apt-get -o DPkg::Lock::Timeout=300 update
apt-get \
  -o DPkg::Lock::Timeout=300 \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  --assume-yes \
  full-upgrade

packages=(
  bash
  build-essential
  ca-certificates
  cloud-init
  curl
  dbus
  git
  git-lfs
  gnupg
  jq
  openssh-client
  rsync
  sudo
)
apt-get \
  -o DPkg::Lock::Timeout=300 \
  --assume-yes \
  --no-install-recommends \
  install "${packages[@]}"

install --directory --owner=root --group=root --mode=0755 \
  /usr/share/keyrings
curl \
  --fail \
  --location \
  --retry 5 \
  https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 \
  | gpg --dearmor --yes \
    --output /usr/share/keyrings/buildkite-agent-archive-keyring.gpg

cat >/etc/apt/sources.list.d/buildkite-agent.list <<'EOF'
deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main
EOF
apt-get -o DPkg::Lock::Timeout=300 update
apt-get \
  -o DPkg::Lock::Timeout=300 \
  --assume-yes \
  --no-install-recommends \
  install buildkite-agent

# The controller starts one job-pinned agent from instance user data. Never
# allow the package's generic, queue-polling service to start from this image.
systemctl disable --now buildkite-agent.service || true
systemctl mask buildkite-agent.service

command -v buildkite-agent
buildkite-agent --version

agent_home="$(getent passwd buildkite-agent | cut -d: -f6)"
if [[ "${agent_home}" != "/var/lib/buildkite-agent" ]]; then
  echo "Unexpected buildkite-agent home: ${agent_home}" >&2
  exit 1
fi
install \
  --directory \
  --owner=buildkite-agent \
  --group=buildkite-agent \
  --mode=0755 \
  "${agent_home}/builds"

# Cloud-init uses setpriv to launch the agent without retaining root access.
command -v setpriv
