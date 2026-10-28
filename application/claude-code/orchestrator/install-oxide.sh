#!/bin/sh
set -eu

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT INT TERM

oxide_asset=oxide-cli-x86_64-unknown-linux-gnu.tar.xz
oxide_url=https://github.com/oxidecomputer/oxide.rs/releases/latest/download
curl -fsSL --retry 5 "$oxide_url/$oxide_asset" \
  -o "$workdir/$oxide_asset"
curl -fsSL --retry 5 "$oxide_url/$oxide_asset.sha256" \
  -o "$workdir/$oxide_asset.sha256"
(cd "$workdir" && sha256sum --check "$oxide_asset.sha256")
tar -xJf "$workdir/$oxide_asset" -C "$workdir"
install -m 0755 \
  "$workdir/oxide-cli-x86_64-unknown-linux-gnu/oxide" \
  /usr/local/bin/oxide

/usr/local/bin/oxide version
