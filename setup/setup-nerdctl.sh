#!/usr/bin/env bash
# OPTIONAL variant: containerd + nerdctl + BuildKit inside WSL2 (instead of Docker Engine).
# Trade-offs vs Docker Engine: docs/nerdctl-variant.md
# Run as a normal user (asks sudo). Debian/Ubuntu only.
#
# Kit-wide mutation policy:
#   ./setup/setup-nerdctl.sh            # consent gate before any change
#   --dry-run / KIT_DRY_RUN=1           # print every change, execute nothing
#   --yes     / KIT_YES=1               # unattended (no prompt)
set -euo pipefail

KIT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# shellcheck source=lib/common.sh
source "$KIT_LIB"

kit_require_wsl2

# --- flags ---------------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: setup/setup-nerdctl.sh [--dry-run] [--yes] [-h|--help]

  --dry-run   print every change, execute nothing   (alias: KIT_DRY_RUN=1)
  --yes       no consent prompt - unattended runs   (alias: KIT_YES=1)
  -h, --help  this text

Version overrides: NERDCTL_VERSION/BUILDKIT_VERSION/CNI_VERSION env vars
(custom versions need matching *_SHA256 env vars, or checksum verification is
skipped with a warning). Other kit guards: KIT_ALLOW_LINUX=1, KIT_ALLOW_ROOT=1.
USAGE
}

KIT_DRY_RUN="${KIT_DRY_RUN:-0}"
KIT_YES="${KIT_YES:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) KIT_DRY_RUN=1 ;;
    --yes)     KIT_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $arg"; usage >&2; exit 2 ;;
  esac
done
export KIT_DRY_RUN KIT_YES

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
  if kit_is_dry_run; then
    info "$label: sha256 verification deferred to the real run (dry-run)"
    return 0
  fi
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

TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="$(id -un 2>/dev/null || true)"
fi
[[ -n "$TARGET_USER" ]] || { warn "Cannot determine the invoking user (SUDO_USER/USER/id all unavailable)."; exit 1; }

kit_consent "nerdctl-variant plan:
  - apt: install containerd + curl
  - /opt/cni/bin: extract CNI plugins ${CNI_VERSION} (sha256-verified tarball)
  - /usr/local/bin: nerdctl ${NERDCTL_VERSION} (sha256-verified tarball)
  - /usr/local: BuildKit ${BUILDKIT_VERSION} (sha256-verified tarball)
  - systemd: enable containerd + buildkitd services
  - wsl.conf: write systemd=true only if missing (restart needed afterwards)
  - group: add '$TARGET_USER' to containerd group"

info "Installing containerd"
kit_run sudo apt-get update
kit_run sudo apt-get install -y containerd curl

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

info "Installing CNI plugins ${CNI_VERSION}"
kit_run curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${CNI_ARCH}-${CNI_VERSION}.tgz" -o "$tmp/cni.tgz"
verify_sha "$tmp/cni.tgz" "$(pin_sha "$CNI_VERSION" "$DEFAULT_CNI_VERSION" "$CNI_SHA256_DEFAULT")" "CNI plugins"
kit_run sudo mkdir -p /opt/cni/bin
kit_run sudo tar -C /opt/cni/bin -xzf "$tmp/cni.tgz"

info "Installing nerdctl ${NERDCTL_VERSION}"
kit_run curl -fsSL "https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-${NERDCTL_ARCH}.tar.gz" -o "$tmp/nerdctl.tgz"
verify_sha "$tmp/nerdctl.tgz" "$(pin_sha "$NERDCTL_VERSION" "$DEFAULT_NERDCTL_VERSION" "$NERDCTL_SHA256_DEFAULT")" "nerdctl"
kit_run sudo tar -C /usr/local/bin -xzf "$tmp/nerdctl.tgz"

info "Installing BuildKit ${BUILDKIT_VERSION}"
kit_run curl -fsSL "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION#v}.linux-${BUILDKIT_ARCH}.tar.gz" -o "$tmp/buildkit.tgz"
verify_sha "$tmp/buildkit.tgz" "$(pin_sha "$BUILDKIT_VERSION" "$DEFAULT_BUILDKIT_VERSION" "$BUILDKIT_SHA256_DEFAULT")" "BuildKit"
kit_run sudo tar -C /usr/local -xzf "$tmp/buildkit.tgz" --strip-components=1 --wildcards '*/bin/*'

# systemd for containerd + buildkitd
if ! grep -qs 'systemd=true' /etc/wsl.conf; then
  info "Enabling systemd in /etc/wsl.conf"
  # Herestring, not `printf |`: dry-run's kit_run does not read stdin, so a
  # pipe producer would die of SIGPIPE (rc 141).
  kit_run sudo tee -a /etc/wsl.conf > /dev/null <<< $'\n[boot]\nsystemd=true\n'
  warn "After this script: 'wsl --shutdown' from Windows, reopen, then re-run this script."
  if kit_is_dry_run; then kit_dry_run_footer; fi
  exit 0
fi

info "Enabling containerd and buildkitd services"
kit_run sudo systemctl enable --now containerd
kit_run sudo systemctl enable --now buildkitd

info "Adding '$TARGET_USER' to the containerd group"
kit_run sudo groupadd containerd 2>/dev/null || true
kit_run sudo usermod -aG containerd "$TARGET_USER"

if kit_is_dry_run; then
  kit_dry_run_footer
  exit 0
fi

info "Done."
cat <<'NEXT'

Next steps:
  1. Apply group membership:  log out & back in (or: newgrp containerd)
  2. Sanity check:            nerdctl run --rm hello-world
  3. Docs & trade-offs:       docs/nerdctl-variant.md

NEXT
