#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
  echo "${0} must run as root" >&2
  exit 1
fi

: "${BUILD_USER:?BUILD_USER must be set}"

build_home="$(getent passwd "${BUILD_USER}" | cut -d: -f6)"
if [[ -z "${build_home}" ]]; then
  echo "Unable to find the home directory for ${BUILD_USER}" >&2
  exit 1
fi

apt-get clean
rm -rf /var/lib/apt/lists/*

rm -f "${build_home}/.ssh/authorized_keys"
rm -f "${build_home}/.ssh/authorized_keys2"
rm -f /root/.ssh/authorized_keys /root/.ssh/authorized_keys2
rm -f /etc/ssh/ssh_host_*

rm -f /boot/loader/random-seed
rm -f /etc/hostname
rm -f /etc/machine-info
rm -f /var/lib/systemd/credential.secret

cloud-init clean --logs --machine-id
systemctl stop systemd-random-seed.service || true
rm -f /var/lib/systemd/random-seed

journalctl --rotate || true
journalctl --vacuum-time=1s || true
find /var/log -type f ! -path '/var/log/journal/*' -exec truncate -s 0 {} +
rm -f /root/.bash_history "${build_home}/.bash_history"
find /tmp /var/tmp -mindepth 1 -delete

sync
