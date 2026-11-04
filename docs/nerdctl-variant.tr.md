# Opsiyonel varyant: containerd + nerdctl

Kitin varsayılanı Docker Engine'dir çünkü CLI/buildx uyumluluğu en geniştir. Bir adım
daha hafif gitmek ve doğrudan **containerd**'nin (Docker'ın kendisinin de kullandığı,
dockershim kaldırılmasından beri Kubernetes'in varsayılan runtime'ı) üzerine oturmak
istiyorsanız `setup/setup-nerdctl.sh` şunları kurar:

- **containerd** — daemon
- **nerdctl** — Docker-uyumlu CLI (`nerdctl run` ≈ `docker run`)
- **BuildKit** — `buildkitd` + `buildctl`, katman-cache build'leri çalışmaya devam etsin
- **CNI plugins** — konteyner ağları

Referanslar: [nerdctl rehberi](https://jacar.es/en/nerdctl-a-lightweight-docker-alternative-over-containerd),
[containerd/nerdctl GitHub](https://github.com/containerd/nerdctl). English:
[nerdctl-variant.md](nerdctl-variant.md).

## Docker Engine'e karşı trade-off'lar

| | Docker Engine | containerd + nerdctl |
|---|---|---|
| CLI uyumluluğu | her şey | çoğu çekirdek komut; bazı flag/plugin farklılıkları |
| `docker buildx` | evet | `nerdctl build` (altında BuildKit, benzer flagler) |
| `docker compose` | compose plugin | `nerdctl compose` (alt küme) |
| Socket yolları | `/var/run/docker.sock` | `/run/containerd/containerd.sock` |
| Docker socket'i bekleyen ekosistem araçları | çalışır | `DOCKER_HOST`-tipi shim'ler gerekebilir veya çalışmaz |
| Ayak izi | biraz daha büyük (dockerd) | biraz daha küçük |

Pratik kural: araçlarınız Docker socket'ine sert bağımlılık yapmıyorsa nerdctl;
IDE konteyner entegrasyonları, compose-ağır iş akışları veya `docker` bekleyen
üçüncü parti araçlar kullanıyorsanız Docker Engine.

## Kurulum sonrası kullanım

```bash
nerdctl run --rm hello-world
nerdctl build -t myapp .
nerdctl compose -f docker-compose.yaml up -d
buildctl --addr unix:///run/buildkit/buildkitd.sock build --help
```

Paylaşımlı-registry cache deseni yine geçerlidir — `nerdctl build` altında BuildKit
vardır; CI'ye bağlamadan önce kurulu sürümünüzde `nerdctl build --help` ile
`--cache-from/--cache-to` desteğini kontrol edin.

## Kaldırma / geri dönme

İki runtime bir arada var olabilir ama ikisi de ağı ve `iptables` yönetimini isteyebilir.
Distro başına birini seçin:

```bash
sudo systemctl disable --now buildkitd containerd   # nerdctl'den çıkmak için
sudo apt-get purge -y containerd                    # + /usr/local/bin/{nerdctl,buildctl,buildkitd} sil
```
