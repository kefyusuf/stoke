# Registry pull-through mirror

Base image'lar (`alpine`, `node`, `python`, …) her geliştirici ve her CI runner'ı
tarafından yeniden indirilir. Pull-through mirror tek yerel kopya tutar: ilk pull
Docker Hub'dan getirir ve cache'ler, herkes mirror'dan çeker.

Bu kitteki kurulum: proxy modunda resmi `registry:2` imajı. Referans:
[Docker — mirror the Docker Hub library](https://docs.docker.com/docker-hub/image-library/mirror/).
Türkçe: bu sayfa. English: [registry-mirror.md](registry-mirror.md).

## Mirror'ı çalıştır

```bash
docker compose -f cache-stack/docker-compose.mirror.yml up -d
# 127.0.0.1:5001'de hizmet verir
```

Compose dosyası [`cache-stack/config/mirror-config.yml`](../cache-stack/config/mirror-config.yml)
dosyasını mount eder; proxy stanza'sı şudur:

```yaml
proxy:
  remoteurl: https://registry-1.docker.io
```

## Docker daemon'ı ona yönlendir

WSL distrosu içinde `/etc/docker/daemon.json`'ı düzenleyin
(şablon: [`templates/daemon-mirror.json`](../templates/daemon-mirror.json)):

```json
{
  "registry-mirrors": ["http://127.0.0.1:5001"]
}
```

Sonra `sudo systemctl restart docker`. `docker pull alpine` artık mirror üzerinden geçer.

`127.0.0.0/8` üzerindeki `registry-mirrors` girdileri otomatik olarak insecure kabul
edilir — bu yerel deployment için TLS kurulumu gerekmez.

## Sınırlar — büyütmeden önce okuyun

[Resmi docs](https://docs.docker.com/docker-hub/image-library/mirror/)'tan:

1. **Read-only.** Pull-through cache'e push yapılamaz; yalnızca cache'lenmiş pull'lara
   hizmet verir. Kendi imajlarınız ve buildcache ref'i *ayrı* bir registry'de yaşar
   ([docker-compose.registry.yml](../cache-stack/docker-compose.registry.yml)) — kitin
   iki compose dosyası göndermesinin sebebi bu.
2. **Tek upstream.** Bir mirror tam olarak tek upstream registry'yi proxy'ler.
   `ghcr.io`, `quay.io` vb.'den gelen imajlar onu bypass eder.
3. **Yalnızca üzerinden geçenleri cache'ler** — bir ekip arkadaşı bir tag'i en az bir
   kez çekmeden mirror'da var olmaz.

Çoklu upstream, push-through veya ekip-geneli deployment gerekiyorsa
[Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
veya [rpardini/docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy)'ye
geçin — kitin local-first tasarımının kapsamı dışındadır.

## Test etme

```bash
docker compose -f cache-stack/docker-compose.mirror.yml up -d
docker pull alpine:3.20                 # ilk pull: mirror üzerinden getirilir, cache'lenir
docker compose -f cache-stack/docker-compose.mirror.yml down
docker compose -f cache-stack/docker-compose.mirror.yml up -d
docker rmi alpine:3.20
time docker pull alpine:3.20            # ikinci pull: yerel diskten servis edilir
```
