# Docker Desktop ile birlikte yaşamak (geçiş ve bir arada kullanım)

English: [migration.md](migration.md)

Önce kısa cevap: **Bu kit için Docker Desktop'ı kaldırmak zorunda değilsiniz.** Kitin
hedefi daha hafif bir makine — kaldırma yalnızca o hedefin *son* adımıdır ve kararı
size aittir (sonsuza kadar ertelemek de bir karardır). Üç dürüst seçenek:

| Seçenek | Kaynak maliyeti | Ne zaman seçilir |
|---|---|---|
| **A. Kurulu ama kapalı** (Desktop hiç çalışmaz) | ~2–3 GB disk; RAM/CPU yok | Kazancın çoğunu sıfır riskle istiyorsanız — dengeli varsayılan |
| **B. Tam paralel** (iki motor da çalışır) | İkisi çalışırken ikisinin de RAM'i | Desktop'ın GUI/Kubernetes düğmesine *ve* kit motoruna günlük ihtiyaç varsa |
| **C. Kaldır** | RAM tamamen geri | A/B seçeneği haftalarca sağlam kaldıysa; ölçülmüş VMMEM düşüşü doğruladıysa |

## A seçeneği — kurulu ama kapalı (kontrol listesi)

1. Docker Desktop → Settings → General → **"Start Docker Desktop when you sign in"
   işaretini kaldır** (varsayılanı AÇIKTIR — bunu yapmazsanız sessizce yine çalışır).
2. Settings → Resources → **WSL Integration → kit distronuz KAPALI** olsun. Açık
   kalırsa Desktop kendi socket'ini distroya enjekte eder ve kitin bağımsız motoru
   gölgelenebilir.
3. Reboot, sonra doğrulayın: `wsl -l -v` → `docker-desktop` **Stopped** görünmeli.
   Maliyetin tamamı bu: sıfır.
4. Günlükte ne değişir: Windows tarafındaki `docker` CLI, Desktop'a aittir — Desktop
   kapalıyken "cannot connect" der. Motorunuz distroda:
   ```powershell
   wsl -d Ubuntu-24.04 -- docker ps      # PowerShell'den
   ```
   ya da distro terminalini açıp `docker`'ı alışıldığı gibi kullanın.

### Zorunlu kılıınmış izolasyon — GUI düğmesinin ötesinde

Yukarıdaki iki düğme Desktop tarafı ayarlarıdır: bir Desktop güncellemesi, yeniden
kurulum veya makineyi paylaşan bir ekip arkadaşı bunları sessizce geri açabilir.
`setup/protect-distro.sh` bunun yerine *distro tarafını* korur — engine kurulumundan
sonra ve her Desktop güncellemesinden sonra `check` koşun:

```bash
./setup/protect-distro.sh check     # CLI ve socket'e kim sahip? enjeksiyonda exit≠0
./setup/protect-distro.sh fix       # root: Desktop artefaktlarını temizle + context'i pinle
```

Üç enjeksiyon mekanizmasını da tespit eder (`/mnt/wsl/docker-desktop`'a giden
`/usr/local/bin` symlink'leriyle CLI gölgelendirme, `/var/run/docker.sock`'un
kaçırılması ve `docker-desktop-proxy` systemd unit'i), temizler ve kullanıcının
varsayılan docker **context'ini** yerel socketa pinler — böylece yeniden enjekte
edilmiş bir Desktop CLI bile kitin motoruyla konuşur. Fix geri döndürülebilirdir:
Desktop'ta WSL Integration'ı yeniden açıp `systemctl unmask <unit>` yaparsınız.

## B seçeneği — tam paralel (iki motor aynı anda)

Bu, doğrulanmış olarak çalışıyor (Windows CLI → Desktop motoru; distro CLI → kitin
motoru; bağımsız daemon'lar, ayrı imaj store'ları). Tek sert kural ve bir alışkanlık:

- **Kural: aynı Windows tarafı portunu asla iki motordan birden publish etmeyin.**
  İkisi de Windows localhost'a iletilir; Desktop'taki `127.0.0.1:5000` ile WSL
  motorundaki `127.0.0.1:5000` çakışır. Bu kitteki tüm compose dosyaları `127.0.0.1`
  bind eder ve bu notu taşır.
- Alışkanlık: *hangi* motorla konuştuğunuzu bilin. Windows tarafındaki `docker` →
  Desktop. Distro içinde → kit motoru. Her iki tarafta `docker context ls` gösterir.

## C seçeneği — kaldırma

- **Ne zaman**: A/B ile birkaç hafta sonra, Task Manager'daki `VMMEM`'i Desktop açıkken
  ve kapalıyken karşılaştırın — veriye bakarak karar verin.
- **Nasıl**: Windows Uygulamalar → yalnızca *Docker Desktop*'ı kaldırın. Distro, kitin
  motoru ve `~/work`'teki her şey dokunulmaz kalır (imajlar distro motorunun
  store'undadır, Desktop'ın değil).
- **Geri dönüş**: istediğiniz zaman yeniden kurun. Bu kitin hiçbir parçası Desktop'ın
  yokluğuna bağımlı değildir.

## Ne paylaşılmıyor, ne paylaşıyor

| | Docker Desktop motoru | Kit motoru (distro içinde) |
|---|---|---|
| İmajlar, konteynerler, volume'lar | kendi store'u | kendi store'u |
| Build cache | kendi builder durumu | kendi builder durumu |
| Paylaşımlı BuildKit registry cache ref'i (`CACHE_REF`) | **paylaşımlı** (registry'de) | **paylaşımlı** |
| ext4 üzerindeki proje kaynakları | paylaşımlı (aynı dosyalar) | paylaşımlı |

Motorlar yerel durumu paylaşmaz — birinde build ederseniz diğeri *yerel olarak* soğuk
kalır; aradaki köprü registry cache ref'idir (ve CI ile de öyle).

İlgili: [faq.tr.md](faq.tr.md) · [setup-wsl2.tr.md](setup-wsl2.tr.md) · [cache-guide.tr.md](cache-guide.tr.md)
