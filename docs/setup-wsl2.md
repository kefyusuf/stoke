# Manual WSL2 + Docker Engine setup

What `setup/setup-wsl.ps1` and `setup/setup-engine.sh` automate, spelled out step by step.
Use this if you prefer doing it by hand or need to debug the scripts.

> Why not Docker Desktop: [evidence #1](evidence.md#1-docker-desktop-carries-a-heavy-idle-footprint-engine-in-wsl2-is-much-lighter).
> Why ext4, not `/mnt/c`: [evidence #2](evidence.md#2-mntc-is-a-build-speed-trap-ext4-is-near-native).

## 1. Install WSL2

Admin PowerShell:

```powershell
wsl --install                 # WSL2 + default Ubuntu distro, requires a reboot
wsl --set-default-version 2
```

Already have WSL? Check the version of your distro — it must be `VERSION 2`:

```powershell
wsl -l -v
wsl --set-version <DistroName> 2
```

A distro running as WSL1 has **no Docker Engine support** — converting to v2 is mandatory.

## 2. Cap the VM with `%UserProfile%\.wslconfig`

Copy `setup/.wslconfig.template` to `%UserProfile%\.wslconfig` and adjust:

```ini
[wsl2]
memory=6GB        # hard cap for the whole VM (shows up in Task Manager as VMMEM)
processors=4      # logical cores visible to the VM
swap=2GB

[experimental]
autoMemoryReclaim=gradual   # return idle cached memory to Windows (WSL 2.0+)
sparseVhd=true              # shrink the ext4 disk file after deletions (WSL 2.0+)
```

Apply with `wsl --shutdown` (next launch picks it up). Reference:
[Microsoft — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

Sizing rule of thumb: `memory` ≈ 1/3–1/2 of host RAM; leave the rest to Windows and the
browser, which are usually the real memory hogs.

## 3. Keep sources inside the distro

```bash
mkdir -p ~/work && cd ~/work
git clone <your-project>
```

- Editing: VS Code → *Remote-WSL: Connect* (or JetBrains Gateway). The editor runs a
  small server inside WSL; you work on Windows as usual while the files physically live
  on ext4.
- **Never build from `/mnt/c/...`** — verify with `pwd`; if it starts with `/mnt/`, move
  the clone.

## 4. Enable systemd (needed for the docker service)

In the distro, `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Then `wsl --shutdown` from Windows once. (Ubuntu 22.04+ ships with this enabled.)

## 5. Install Docker Engine

Run `setup/setup-engine.sh`, or by hand:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # log out/in afterwards, or `newgrp docker`
```

On **Debian**, swap `linux/ubuntu` for `linux/debian` in both URLs (the repo key
and apt source are separate per distro). Upstream reference:
[Docker — install on Ubuntu](https://docs.docker.com/engine/install/ubuntu/).

## 6. Sanity check

```bash
docker version          # client + server, no sudo
docker buildx version   # BuildKit frontend
docker run --rm hello-world
```

If `docker version` needs sudo, you skipped the group step — log out/in of WSL.

## Daily workflow

| Task | Command |
|---|---|
| Start work | open terminal → distro is auto-started; docker runs as a systemd service |
| Check VM footprint | Task Manager → `VMMEM` (should sit at your `memory=` cap at most) |
| Full reset | `wsl --shutdown` from PowerShell |
| Free disk after big cleanups | `wsl --manage <DistroName> --set-sparse true` (or rely on `sparseVhd`) |

Next: [cache-guide.md](cache-guide.md) to wire the shared build cache.
