# Registry pull-through mirror

Türkçe: [registry-mirror.tr.md](registry-mirror.tr.md)

Base images (`alpine`, `node`, `python`, …) get re-downloaded by every developer and
every CI runner. A pull-through mirror keeps one local copy: first pull fetches from
Docker Hub and caches it, everyone else pulls from the mirror.

Setup used in this kit: the official `registry:2` image in proxy mode.
Reference: [Docker — mirror the Docker Hub library](https://docs.docker.com/docker-hub/image-library/mirror/).

## Run the mirror

```bash
docker compose -f cache-stack/docker-compose.mirror.yml up -d
# serves on 127.0.0.1:5001
```

The compose file mounts [`cache-stack/config/mirror-config.yml`](../cache-stack/config/mirror-config.yml),
which adds the proxy stanza:

```yaml
proxy:
  remoteurl: https://registry-1.docker.io
```

## Point the Docker daemon at it

Edit `/etc/docker/daemon.json` inside the WSL distro (template: [`templates/daemon-mirror.json`](../templates/daemon-mirror.json)):

```json
{
  "registry-mirrors": ["http://127.0.0.1:5001"]
}
```

Then `sudo systemctl restart docker`. `docker pull alpine` now goes through the mirror.

`registry-mirrors` entries on `127.0.0.0/8` are treated as insecure automatically — no
TLS setup needed for this local-only deployment.

## Limits — read before scaling this up

From the [official docs](https://docs.docker.com/docker-hub/image-library/mirror/):

1. **Read-only.** You cannot push to a pull-through cache; it only serves cached pulls.
   Your own images and the buildcache ref live in a *separate* registry
   ([docker-compose.registry.yml](../cache-stack/docker-compose.registry.yml)) — that's
   why this kit ships two compose files.
2. **Single upstream.** One mirror proxies exactly one upstream registry. Images from
   `ghcr.io`, `quay.io` etc. bypass it.
3. **It only caches what flows through it** — a teammate must pull a tag at least once
   before it exists in the mirror.

If you need multi-upstream, push-through, or team-wide deployment, graduate to
[Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
or [rpardini/docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy) —
out of scope for this kit's local-first design.

## Testing it

```bash
docker compose -f cache-stack/docker-compose.mirror.yml up -d
docker pull alpine:3.20                 # first pull: fetched via mirror, cached
docker compose -f cache-stack/docker-compose.mirror.yml down
docker compose -f cache-stack/docker-compose.mirror.yml up -d
docker rmi alpine:3.20
time docker pull alpine:3.20            # second pull: served from local disk
```
