#!/usr/bin/env bash
# OPTIONAL variant: containerd + nerdctl + BuildKit inside WSL2 (instead of Docker Engine).
# Trade-offs vs Docker Engine: see docs/nerdctl-variant.md.
# Run as a normal user (asks sudo). Debian/Ubuntu only.
set -euo pipefail

info()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] && { warn "Run this as your normal user (it uses sudo internally), not as root."; exit 1; }
command -v apt-get >/dev/null || { warn "Debian/Ubuntu (apt) required."; exit 1; }

# Pin versions AND tarball checksums (sha256) for reproducibility; override the
# env vars if you need newer releases. If you override a VERSION, also pass the
# matching *_SHA256 (or leave it empty to skip verification with a warning).
DEFAULT_NERDCTL_VERSION=v2.0.3
DEFAULT_BUILDKIT_VERSION=v0.17.3
DEFAULT_CNI_VERSION=v1.5.1
NERDCTL_VERSION="${NERDCTL_VERSION:-$DEFAULT_NERDCTL_VERSION}"
BUILDKIT_VERSION="${BUILDKIT_VERSION:-$DEFAULT_BUILDKIT_VERSION}"
CNI_VERSION="${CNI_VERSION:-$DEFAULT_CNI_VERSION}"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  NERDCTL_ARCH=amd64;  BUILDKIT_ARCH=amd64;  CNI_ARCH=amd64
           NERDCTL_SHA256_DEFAULT=95ff850688a73eace7453f19e74bf4cc8a1f3e458eeb97ef7a6b74de9825df16
           BUILDKIT_SHA256_DEFAULT=1ab54cc01fd2e174483070451921badc53cc463a4f2e2e980be7db99ca95c0d0
           CNI_SHA256_DEFAULT=77baa2f669980a82255ffa2f2717de823992480271ee778aa51a9c60ae89ff9b ;;
  aarch64) NERDCTL_ARCH=arm64;  BUILDKIT_ARCH=arm64;  CNI_ARCH=arm64
           NERDCTL_SHA256_DEFAULT=f2c3f12c99e112cd82ba19ca9b875045c44b2f5a19cecc295ed8d61d415e8851
           BUILDKIT_SHA256_DEFAULT=1afabc9c0829f7fa5173f439b7212194703b48f8e79a405596ada1af6e6f8220
           CNI_SHA256_DEFAULT=c2a292714d0fad98a3491ae43df8ad58354b3c0bdf5d5a3e281777967c70fcff ;;
  *) warn "Unsupported arch: $ARCH"; exit 1 ;;
esac

# sha256 is only pinned for the default versions; custom versions need explicit hashes.
pin_sha() { # <VERSION> <DEFAULT_VERSION> <SHA_DEFAULT> -> echoes sha or empty
  if [ "$1" = "$2" ]; then echo "$3"; fi
}
verify_sha() { # <file> <expected-sha> <label>
  local file="$1" want="$2" label="$3"
  if [ -z "$want" ]; then
    warn "$label: no pinned sha256 (custom version?) - SKIPPING checksum verification"
    return 0
  fi
  local got
  got=$(sha256sum "$file" | awk '{print $1}')
  if [ "$got" != "$want" ]; then
    warn "$label sha256 MISMATCH: got $got, expected $want - aborting (tarball tampered or wrong version)"
    exit 1
  fi
  info "$label sha256 verified"
}

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
verify_sha "$tmp/cni.tgz" "$(pin_sha "$CNI_VERSION" "$DEFAULT_CNI_VERSION" "$CNI_SHA256_DEFAULT")" "CNI plugins"
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf "$tmp/cni.tgz"

info "Installing nerdctl ${NERDCTL_VERSION}"
curl -fsSL "https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-${NERDCTL_ARCH}.tar.gz" -o "$tmp/nerdctl.tgz"
verify_sha "$tmp/nerdctl.tgz" "$(pin_sha "$NERDCTL_VERSION" "$DEFAULT_NERDCTL_VERSION" "$NERDCTL_SHA256_DEFAULT")" "nerdctl"
sudo tar -C /usr/local/bin -xzf "$tmp/nerdctl.tgz"

info "Installing BuildKit ${BUILDKIT_VERSION}"
curl -fsSL "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION#v}.linux-${BUILDKIT_ARCH}.tar.gz" -o "$tmp/buildkit.tgz"
verify_sha "$tmp/buildkit.tgz" "$(pin_sha "$BUILDKIT_VERSION" "$DEFAULT_BUILDKIT_VERSION" "$BUILDKIT_SHA256_DEFAULT")" "BuildKit"
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
