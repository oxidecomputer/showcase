#!/bin/sh
set -eu

: "${CLAUDE_VERSION:?CLAUDE_VERSION unset}"

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

claude_url=https://downloads.claude.ai/claude-code-releases/$CLAUDE_VERSION
export GNUPGHOME="$workdir/gnupg"
install -d -m 0700 "$GNUPGHOME"
curl -fsSL --retry 5 https://downloads.claude.ai/keys/claude-code.asc \
  -o "$workdir/claude-code.asc"
gpg --batch --import "$workdir/claude-code.asc"
fingerprint="$(gpg --batch --with-colons --fingerprint security@anthropic.com \
  | awk -F: '$1 == "fpr" { print $10; exit }')"
[ "$fingerprint" = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" ]

curl -fsSL --retry 5 "$claude_url/manifest.json" \
  -o "$workdir/manifest.json"
curl -fsSL --retry 5 "$claude_url/manifest.json.sig" \
  -o "$workdir/manifest.json.sig"
gpg --batch --verify "$workdir/manifest.json.sig" "$workdir/manifest.json"

curl -fsSL --retry 5 "$claude_url/linux-x64/claude" \
  -o "$workdir/claude"
claude_checksum="$(jq -er '.platforms["linux-x64"].checksum' \
  "$workdir/manifest.json")"
printf '%s  %s\n' "$claude_checksum" "$workdir/claude" \
  | sha256sum --check -
install -m 0755 "$workdir/claude" /usr/local/bin/claude

/usr/local/bin/oxide version
/usr/local/bin/claude --version
