# Kanıtlar

Bu kitin yaptığı her performans/lisans iddiası, kaynaklarıyla birlikte. Rakamlar üçüncü
taraf ölçümleridir — makineye ve iş yüküne göre değişir. En kritik iki iddiayı (cache'li
build hızlanması ve registry cache döngüsü) `setup/verify.sh` **kendi donanımında**
yeniden üretir.

## İddialar

### 1. Docker Desktop boşta bile ağır; WSL2 içinde Engine çok daha hafif

- Docker Desktop (WSL2 backend) boşta ~**2–3 GB RAM** tüketir; `VMMEM` süreci başlangıç
  sonrası ~2 GB tutar ve bırakmaz. Kaynaklar: [Docker forums — idle memory](https://forums.docker.com/t/docker-desktop-idle-memory-usage/138540),
  [docker/for-win#12944](https://github.com/docker/for-win/issues/12944)
- Docker Desktop'tan WSL2 içinde manuel Docker Engine kurulumuna geçmek kaynak kullanımını
  **yaklaşık yarıya indirdi** ve boşta arka plan CPU uyanmalarını kesti. Kaynak:
  [XDA — Docker through WSL instead of Docker Desktop](https://www.xda-developers.com/running-docker-through-wsl-instead-docker-desktop-cut-resource-usage-half)
- `.wslconfig` sınırı yokken WSL2 host RAM'inin **%50–80'ini** alabiliyor; sınır koymak
  resmi mekanizma. Kaynak: [Microsoft — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)

### 2. `/mnt/c` bir build-hızı tuzağı; ext4 neredeyse native

- Benchmark: WSL2 ext4 native Linux'a yakın çalışırken `/mnt/c` üzerinden NTFS erişimi
  yaklaşık **5x daha yavaş** (9P protokol sınırı). Kaynaklar:
  [vxlabs WSL2 I/O ölçümleri](https://vxlabs.com/2019/12/06/wsl2-io-measurements),
  [microsoft/WSL#4197](https://github.com/microsoft/WSL/issues/4197),
  [Stack Overflow — npm/yarn yavaşlığı (9P)](https://stackoverflow.com/questions/68972448/why-is-wsl-extremely-slow-when-compared-with-native-windows-npm-yarn-processing)
- Pratik sonuç: kaynakları ve repo klonunu distro içinde (`~/work`) tut; Windows'tan
  VS Code Remote-WSL ile düzenle.

### 3. `.wslconfig` resmi kaynak sınırıdır

- `[wsl2]` altında `memory`, `processors`, `swap`; `wsl --shutdown` sonrası uygulanır.
  Kaynak: [Microsoft — gelişmiş WSL ayarları](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)
- Yeni WSL sürümlerinde ayrıca `[experimental]` altında boşta önbellek belleğini geri
  veren `autoMemoryReclaim` ve ext4 disk dosyasını küçülten `sparseVhd` var.

### 4. BuildKit registry cache makineler arası katman paylaşır — anahtar `mode=max`

- Resmi cache storage backend'leri (`type=registry|gha|s3|local|…`) ve `cache-from` /
  `cache-to` birleşimi. Kaynak: [Docker docs — cache storage backends](https://docs.docker.com/build/cache/backends)
- `mode=min` (varsayılan) yalnızca son imajın katmanlarını; `mode=max` **tüm ara
  stage'leri** dışa aktarır — makineler arası yeniden kullanım için multi-stage build'de
  bu gerekir. Kaynaklar: [BuildKit docs — cache modes](https://crazymax.dev/buildkit/usage/cache),
  [moby/buildkit#1515](https://github.com/moby/buildkit/issues/1515)
- Aynı mekanizmanın CI rehberi: [GitLab — Docker layer caching](https://docs.gitlab.com/ci/docker/docker_layer_caching/)

### 5. Pull-through mirror base image'ları tek kopyaya indirger — dürüst sınırlarla

- Resmi registry `proxy.remoteurl` ile pull-through cache olarak çalışır; istemciler
  `registry-mirrors` ile bağlanır. Kaynak: [Docker docs — mirror the Docker Hub library](https://docs.docker.com/docker-hub/image-library/mirror/)
- Sınırlar: **read-only**, **tek upstream**, etkin olarak Docker Hub tipi registry'ler;
  yalnızca üzerinden çekilenleri cache'ler. Çoklu upstream için
  [Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
  veya [docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy) gerekir.

### 6. Lisans: Docker Engine, Docker Desktop'ın kişi-başı maliyet baskısını kaldırır

- Docker Desktop, **250'den fazla çalışanı VEYA 10M$+ yıllık cirosu olan** organizasyonlarda
  profesyonel kullanım için ücretli abonelik ister (ikisi de ayrı ayrı tetikler). Kaynak:
  [Docker — Desktop license agreement](https://docs.docker.com/subscription-billing/desktop-license/),
  [Docker pricing](https://www.docker.com/pricing/)
- Docker Engine kendisi Apache-2.0 ve kısıtsız; bu kit asla Docker Desktop kurmaz.

### 7. containerd + nerdctl daha hafif opsiyonel yol

- nerdctl, containerd (dockershim kaldırılmasından beri Kubernetes'in varsayılan runtime'ı)
  üzerine Docker-uyumlu CLI. Kaynaklar: [nerdctl rehberi](https://jacar.es/en/nerdctl-a-lightweight-docker-alternative-over-containerd),
  [alternatiflere genel bakış](https://www.qovery.com/blog/4-best-docker-desktop-alternatives)
- Docker CLI/buildx uyumluluğu daha geniş olduğu için bu kitte opsiyonel varyant olarak
  tutuluyor: [docs/nerdctl-variant.md](nerdctl-variant.md)

### 8. Bağımlılık cache'i: `node_modules`'ü değil, store'u cache'le

- pnpm'in resmi CI rehberi: **pnpm store**'u cache'le (`pnpm store path` ile yolunu al),
  lockfile hash'ine göre anahtarla; `node_modules` store'a hard link tutar, cache'lemek
  etkisiz/kırılgandır. Kaynaklar: [pnpm — CI](https://pnpm.io/continuous-integration),
  [pnpm tartışması #6374](https://github.com/orgs/pnpm/discussions/6374)
- Genel kural: cache anahtarını lockfile hash'ine bağla, CI'da `--frozen-lockfile` kullan.

## Bu kitin kendi ölçümleri

2026-11-04'te kit yazarının makinesinde kaydedildi — **Windows 11 host, WSL2
Ubuntu-24.04 distro, distro içinde Docker Engine 29.9.3**. Tek makine, yol gösterici
rakamlar; `setup/verify.sh`'i kendi makinenizde koşup karşılaştırın.

| Ne | Sonuç |
|---|---|
| `verify.sh` katman-cache hızlanması | **7x** — warm build 1.3 sn vs cold build (base pull dahil) |
| `verify.sh` registry round trip | Builder B (taze, boş store) `--cache-from` ile **CACHED** — iki kez test edildi: Docker Desktop 29.9.2 altında ve distro içi Engine 29.9.3 altında |
| Stack şablonları | **node-ts, rust, go: 6 target'ın tamamı (prod+dev) build edildi; 3 prod konteyneri WSL motorunda HTTP 200 yanıtladı** |
| Gerçek geçiş | Docker Desktop → WSL2-içi Engine canlı yapıldı; örtüşme döneminde iki motor paralel çalıştı |
| Canlı koşuların yakaladığı hatalar | Rust dummy-binary mtime tuzağı (sessiz bayat binary — exit 0, sunucu yok) ve cache-mount katmana yazılmaz tuzağı; ikisi de şablonlarda düzeltildi |

## Kendi kendini doğrulama

```bash
./setup/verify.sh
```

1. Küçük bir imajı iki kez build eder ve hızlanmayı raporlar (katman cache hit'i).
2. Cache'i geçici bir yerel registry'ye yazar, ardından *taze* bir BuildKit builder ile
   `cache-from` üzerinden yeniden build eder — makineler-arası (yerel ⇄ CI) cache
   yeniden kullanımının makinenizde çalıştığını kanıtlar.

RAM iddiası için: Task Manager'daki `VMMEM` değerini, Docker Desktop'ı kaldırıp bu kitin
kurulumuna geçmeden önce/sonra karşılaştır — ve yine de `.wslconfig` ile sınır koy.

## Uyarılar

- Yukarıdaki üçüncü taraf rakamlar yol göstericidir, garanti değildir; disk hızı, proje
  boyutu ve ağ etkilidir. Önce dene, sonra `verify.sh` ile ölç.
- İlk build her zaman soğuktur; kazanç ikinci build'den itibaren görünür.
- CI cache çekmeleri ağ bant genişliği harcar; büyük `mode=max` cache'i yeni bir branch'in
  ilk CI build'ini yavaşlatır, sonrakileri hızlandırır.
