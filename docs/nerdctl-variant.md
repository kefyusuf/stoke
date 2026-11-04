# Optional variant: containerd + nerdctl

The kit's default is Docker Engine because its CLI/buildx compatibility is the broadest.
If you want to go one step lighter and sit directly on **containerd** (the runtime Docker
itself uses, and Kubernetes' default since the dockershim removal), `setup/setup-nerdctl.sh`
installs:

- **containerd** — the daemon
- **nerdctl** — Docker-compatible CLI (`nerdctl run` ≈ `docker run`)
- **BuildKit** — `buildkitd` + `buildctl`, so layer-cache builds still work
- **CNI plugins** — container networking

Reference: [nerdctl overview](https://jacar.es/en/nerdctl-a-lightweight-docker-alternative-over-containerd),
[containerd/nerdctl GitHub](https://github.com/containerd/nerdctl).

## Trade-offs vs Docker Engine

| | Docker Engine | containerd + nerdctl |
|---|---|---|
| CLI compatibility | everything | most core commands; some flags/plugins differ |
| `docker buildx` | yes | `nerdctl build` (BuildKit underneath, similar flags) |
| `docker compose` | compose plugin | `nerdctl compose` (subset) |
| Socket paths | `/var/run/docker.sock` | `/run/containerd/containerd.sock` |
| Ecosystem tools expecting the docker socket | work | may need `DOCKER_HOST`-style shims or don't work |
| Footprint | slightly larger (dockerd) | slightly smaller |

Rule of thumb: choose nerdctl if your tooling doesn't hard-depend on the Docker socket;
choose Docker Engine if you use IDE container integrations, act/compose-heavy workflows,
or third-party tools that assume `docker`.

## Usage after install

```bash
nerdctl run --rm hello-world
nerdctl build -t myapp .
nerdctl compose -f docker-compose.yaml up -d
buildctl --addr unix:///run/buildkit/buildkitd.sock build --help
```

The shared-registry cache pattern still applies — `nerdctl build` is BuildKit underneath;
check `nerdctl build --help` for `--cache-from/--cache-to` support in your installed
version before wiring it into CI.

## Uninstall / switching back

The two runtimes can coexist but both try to manage networking and may fight over
`iptables`. Pick one per distro:

```bash
sudo systemctl disable --now buildkitd containerd   # to leave nerdctl
sudo apt-get purge -y containerd                    # + remove /usr/local/bin/{nerdctl,buildctl,buildkitd}
```
