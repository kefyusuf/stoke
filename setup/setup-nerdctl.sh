#!/usr/bin/env bash
# OPTIONAL variant: containerd + nerdctl + BuildKit inside WSL2 (instead of Docker Engine).
# Trade-offs vs Docker Engine: see docs/nerdctl-variant.md.
# Run as a normal user (asks sudo). Debian/Ubuntu only.
set -euo pipefail

info()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { warn "Run this as your normal user (it uses sudo internally), not as root."; exit 1; }
command -v apt-get >/dev/null || { warn "Debian/Ubuntu (apt) required."; exit 1; }

# Pin versions for reproducibility; override with env vars if you need newer.
NERDCTL_VERSION="${NERDCTL_VERSION:-v2.0.3}"
BUILDKIT_VERSION="${BUILDKIT_VERSION:-v0.17.3}"
CNI_VERSION="${CNI_VERSION:-v1.5.1}"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) NERDCTL_ARCH=amd64;  BUILDKIT_ARCH=amd64;  CNI_ARCH=amd64 ;;
  aarch64) NERDCTL_ARCH=arm64; BUILDKIT_ARCH=arm64;  CNI_ARCH=arm64 ;;
  *) warn "Unsupported arch: $ARCH"; exit 1 ;;
esac

# Don't fight a running dockerd over networking/iptables.
if systemctl is-active docker >/dev/null 2>&1; then
  warn "docker service is ACTIVE in this distro. containerd+nerdctl and dockerd fight over iptables."
  warn "Pick one runtime per distro - disable docker first or use a fresh distro."
  exit 1
fi

info "Installing containerd"
sudo apt-get update
sudo apt-get install -y containerd curl

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

info "Installing CNI plugins ${CNI_VERSION}"
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${CNI_ARCH}-${CNI_VERSION}.tgz" -o "$tmp/cni.tgz"
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf "$tmp/cni.tgz"

info "Installing nerdctl ${NERDCTL_VERSION}"
curl -fsSL "https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-${NERDCTL_ARCH}.tar.gz" -o "$tmp/nerdctl.tgz"
sudo tar -C /usr/local/bin -xzf "$tmp/nerdctl.tgz"

info "Installing BuildKit ${BUILDKIT_VERSION}"
curl -fsSL "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION#v}.linux-${BUILDKIT_ARCH}.tar.gz" -o "$tmp/buildkit.tgz"
sudo tar -C /usr/local -xzf "$tmp/buildkit.tgz" --strip-components=1 --wildcards '*/bin/*'

# systemd for containerd + buildkitd
if ! grep -qs 'systemd=true' /etc/wsl.conf; then
  info "Enabling systemd in /etc/wsl.conf"
  printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf > /dev/null
  warn "After this script: 'wsl --shutdown' from Windows, reopen, then re-run this script."
  exit 0
fi

info "Enabling containerd and buildkitd services"
sudo systemctl enable --now containerd
sudo systemctl enable --now buildkitd

info "Adding '$USER' to the containerd group"
sudo groupadd containerd 2>/dev/null || true
sudo usermod -aG containerd "$USER"

info "Done."
cat <<'NEXT'

Next steps:
  1. Apply group membership:  log out & back in (or: newgrp containerd)
  2. Sanity check:            nerdctl run --rm hello-world
  3. Docs & trade-offs:       docs/nerdctl-variant.md

NEXT
