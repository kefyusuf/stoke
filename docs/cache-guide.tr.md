# Build cache rehberi

Paylaşımlı cache nasıl çalışır ve projen için doğru nasıl kurulur.

Referans: [Docker — cache storage backends](https://docs.docker.com/build/cache/backends).

## Zihinsel model

BuildKit katmanları content-addressed tutar: bir katmanın kimliği, girdilerinin
(base imaj + kopyalanan dosyalar + komut) hash'idir. Bir adımın bağımlı olduğu hiçbir şey
değişmediyse katmanı cache'ten gelir — *cache erişilebilirse*. Bu kit erişilebilirliği iki
yolla sağlar:

1. **Yerel store** — daemon cache'i diskte tutar; ikinci yerel build hızlıdır.
2. **Paylaşımlı registry ref'i** — `cache-from`/`cache-to type=registry`, cache
   manifestlerini bir Docker registry'ye yazar/okur. Registry'ye ulaşabilen her makine —
   senin WSL2 makinen, bir CI runner'ı, bir ekip arkadaşı — aynı cache'i ısıtır veya
   yeniden kullanır.

`templates/build.sh` bunu tek komutta sarar:

```bash
CACHE_REF=127.0.0.1:5000/myapp:buildcache ./build.sh            # yerel registry
CACHE_REF=ghcr.io/org/myapp:buildcache PUSH=1 ./build.sh        # CI ile paylaşımlı
```

Eşdeğer ham komut:

```bash
docker buildx build \
  --cache-from type=registry,ref="$CACHE_REF" \
  --cache-to   type=registry,ref="$CACHE_REF",mode=max \
  --push -t "$IMAGE" .
```

## `mode=min` ve `mode=max`

| | `mode=min` (varsayılan) | `mode=max` |
|---|---|---|
| Dışa aktarır | yalnızca **son stage'in** katmanları | **tüm stage'ler**, ara katmanlar dahil |
| Multi-stage makineler-arası yeniden kullanım | çoğunlukla ıskalar | tam yeniden kullanım |
| Registry'deki cache boyutu | küçük | daha büyük |
| Ne zaman | tek-stage Dockerfile | multi-stage (yaygın durum) — **bu kitin varsayılanı** |

Kaynak: [BuildKit — cache modes](https://crazymax.dev/buildkit/usage/cache/).

## Katman sırası her şeyden önemli

Cache, ilk değişen instruction'dan aşağı doğru geçersizleşir. Klasik ıskalama:
`RUN <bağımlılık kurulumu>`'ndan *önce* `COPY . .` — her kaynak değişikliği tüm
bağımlılıkları yeniden indirir ve kurar. Çözüm lockfile-önce sıralaması:

```dockerfile
COPY package.json pnpm-lock.yaml ./     # cache anahtarı = sadece manifest'ler
RUN --mount=type=cache,target=/root/.local-share-pnpm \
    pnpm install --frozen-lockfile
COPY . .                                # kaynak değişikliği yalnızca buradan geçersizleştirir
RUN pnpm build
```

`templates/Dockerfile` bu iskeleti, gerçek komutların için TODO işaretleriyle gönderir.

## Cache mount'lar ve katmanlar

Büyük cache dizini yazan her şey (paket yöneticileri, derleyiciler) için dizini katmana
gömmek yerine **cache mount** tercih et:

```dockerfile
RUN --mount=type=cache,target=/root/.cache \
    pip install -r requirements.txt
```

- Cache dizini, imajı veya registry cache'ini şişirmeden **aynı builder'da** buildler
  arası kalır.
- Dikkat: cache mount'lar builder'a özgüdür — `cache-to` ile *dışa aktarılmaz*. Yerel
  yeniden build'leri ve self-hosted runner'ları hızlandırır; makineler-arası yeniden
  kullanım yine katman cache'inden gelir. İki mekanizma birbirini tamamlar.

## Bağımlılık store'ları

- `node_modules`/`venv`'yi değil **store'u** cache'le — örn. pnpm store paketleri tutar,
  `node_modules` içine hard link atar ([pnpm CI docs](https://pnpm.io/continuous-integration)).
- Docker'sız CI'da platform cache'ini kullan: GitHub'da `cache: pnpm` ile
  `actions/setup-node`; GitLab'da lockfile anahtarlı `cache:`.

## CI bağlantısı

| Dosya | Mekanizma |
|---|---|
| [`ci/github-actions.yml`](../ci/github-actions.yml) | GHCR'ye karşı `type=registry` — platform-bağımsız kalıp; ref'i değiştirerek GitLab registry vb. ile de çalışır |
| [`ci/github-actions-gha.yml`](../ci/github-actions-gha.yml) | `type=gha` — GitHub'ın dahili cache backend'i; registry gerekmez ama **yalnızca GitHub** (repo başına 10 GB kota, LRU temizlik) |
| [`ci/gitlab-ci.yml`](../ci/gitlab-ci.yml) | GitLab container registry'sine karşı docker:dind ile `type=registry` |

El sıkışmanın çalışması için yerel ve CI **aynı ref'i paylaşmalı** — zaten tüm nokta bu.

## Cache hijyeni

- Paylaşımlı ref zamanla büyür; ara sıra temiz bir builder'dan yeniden oluştur veya CI'yi
  dönen ref'e yönlendir (`buildcache-$(date +%Y-%m)`) ve eskileri sil.
- Self-hosted registry'de silinen manifest alanını registry GC
  (`registry garbage-collect`) geri kazanır.
- Disk dolunca yerel temizlik: `docker builder prune`.

## Iskalama sorun giderme

| Belirti | Sık sebep |
|---|---|
| CI hep soğuk | Yerelin yazdığı ref ile CI'nin `cache-from` ref'i farklı; veya registry auth eksik |
| Kaynak değişince yerel build yeniden yavaşladı | Bağımlılık kurulumunun üstünde bir adım değişiyor (bkz. *Katman sırası*) |
| `mode=max` var ama ara stage'ler CI'de yok | `--cache-to`'daki yazım hatası (dışa aktarana *export* tarafı karar verir) |
| Yerelde çalışıyor, CI'de push başarısız | Ref registry'si o job'da auth/login istiyor |
