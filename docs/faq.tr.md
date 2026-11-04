# SSS / Sorun Giderme

## Kaynaklar ve Windows tarafı

**Task Manager'da kocaman bir `VMMEM` süreci görüyorum.**
O, WSL2 VM'inizin kendisidir. `.wslconfig` (`memory=`) ile sınırlandırılır. Sınıra
oturuyorsa sınırı düşürün; sınır yüksek ama VMMEM günler içinde tırmanıyorsa
`autoMemoryReclaim=gradual` açık mı bakın (WSL 2.0+) ya da derhal geri almak için
`wsl --shutdown` çalıştırın.

**`.wslconfig`'i düzenledim ama hiçbir şey değişmedi.**
VM açılışında uygulanır: PowerShell'den `wsl --shutdown` çalıştırıp distroyu yeniden
açın. Dosyanın distro içinde değil `%UserProfile%\.wslconfig` olduğunu ve BOM/kodlama
sorunu olmadığını da doğrulayın.

**`wsl --install` başarısız ya da özellik eksik.**
Eski Windows 10 sürümlerinde özellikleri elle açın: `dism.exe /online /enable-feature
/featurename:Microsoft-Windows-Subsystem-Linux /all /norestart` ve aynısı
`VirtualMachinePlatform` için, sonra yeniden başlatın. BIOS'ta sanallaştırma açık olmalı.

**Build'ler misteriously yavaş.**
`pwd` yazın. `/mnt/c` altındaki her şey 9P sınırından geçer (~5x yavaş —
[kanıtlar #2](evidence.tr.md#2-mntc-bir-build-hızı-tuzağı-ext4-neredeyse-native)). Klonu
`~/work`'e taşıyın ve VS Code Remote-WSL ile düzenleyin.

## WSL içindeki Docker

**`permission denied ... /var/run/docker.sock`.**
Henüz `docker` grubunda değilsiniz: `sudo usermod -aG docker $USER`, sonra WSL terminalini
kapatıp açın (veya `newgrp docker`).

**`Cannot connect to the Docker daemon`.**
Servis çalışmıyor. systemd açıkken (`/etc/wsl.conf` içinde `[boot] systemd=true`, sonra
`wsl --shutdown`): `sudo systemctl enable --now docker`. systemd yoksa elle başlatın:
`sudo service docker start`.

**Windows bir konteynerin publish edilmiş portuna erişemiyor, ya da localhost yönlendirme
kesildi.**
WSL'i yeniden başlatın (`wsl --shutdown`) — localhost relay'i açılışta yeniden kurulur.
Cache registry'sine başka bir makineden Windows→WSL erişimi gerekiyorsa, bu kitin
kapsamının ötesinde bir ağ adımıdır (yerel registry 127.0.0.1'e bind edilir).

**İmajları sildikten sonra disk küçülmedi.**
ext4 sanal diski büyür ama `sparseVhd=true` (WSL 2.0+) yoksa otomatik küçülmez. Büyük
temizliklerden sonra: `docker system prune`, ardından PowerShell'den
`wsl --manage <DistroName> --set-sparse true`.

## Cache ve buildler

**Yerelde ikinci build hızlı ama CI hep soğuk.**
Yerel ve CI *aynı* `CACHE_REF` registry'sini ve tag'i kullanmalı, ve CI o registry'ye
authenticate olabilmeli (her `ci/` şablonundaki login adımına bakın). Yerel build'lerin
cache'i gerçekten yazdığını da doğrulayın (`--cache-to` hatasız).

**Aynı ref ile cache hit hiç olmuyor.**
İlk *değişen* instruction her şeyi geçersizleştirir. Klasik suçlu: bağımlılık kurulumunun
üstündeki `COPY . .`. Lockfile-first olarak yeniden sıralayın
([cache-guide.tr.md](cache-guide.tr.md#katman-sırası-her-şeyden-önemli)).

**`--cache-to type=registry` `unauthorized` ile başarısız.**
Export, cache *manifestlerini* ref'in registry'sine yazar — önce o registry'ye
`docker login` (CI job dahil).

**`--load` (push yok) ile `--cache-to type=registry` kullanabilir miyim?**
Evet — cache export, imaj export'undan bağımsızdır. `templates/build.sh` `PUSH=0`
olduğunda tam olarak bunu yapar.

**Pull-through mirror kullanılmıyor.**
`/etc/docker/daemon.json` içindeki `registry-mirrors` daemon restart ister, yalnızca
Docker Hub'ı proxy'ler ve birinin üzerinden çektiği tag'lere hizmet verir
([registry-mirror.tr.md](registry-mirror.tr.md)).

**CI'de ara-stage cache'i nereye gitti?**
Varsayılan `mode=min` (yalnız son stage). Bu kit hep `mode=max` koyar — kendi komutunuzu
yazdıysanız export bayrağını kontrol edin.

**Birden çok upstream için mirror gerekiyor (ghcr.io, quay.io, …)?**
Stok pull-through cache tam olarak tek registry'yi proxy'ler. Çoklu upstream veya
ekip-geneli caching için [Harbor proxy cache](https://goharbor.io/docs/2.1.0/administration/configure-proxy-cache/)
veya [docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy)'ye geçin —
"Limits" bölümüne bakın: [registry-mirror.tr.md](registry-mirror.tr.md).

## Script sorunları

**`setup-wsl.ps1` elevation istiyor.**
*Yönetici* PowerShell'den çalıştırın — WSL özellik kurulumu bunu gerektirir.

**`setup-engine.sh` `apt-get update`'te başarısız.**
Docker'ın apt reposu distro kod adına göre türetilir (`/etc/os-release`'den otomatik:
ubuntu→linux/ubuntu, debian→linux/debian). Çok eski veya Ubuntu/Debian dışı distrolar bu
yolda desteklenmez — [setup-wsl2.tr.md](setup-wsl2.tr.md) içindeki manuel adımları
distronuza uyarlayın ya da Ubuntu'ya geçin.

**`verify.sh` registry adımı kullanılan portta çakışıyor.**
30000–49999 arası rastgele port seçer; belirli boş bir port zorlamak için
`KIT_VERIFY_PORT=<port>` export edin.

---
İlgili sayfalar: [registry-mirror.tr.md](registry-mirror.tr.md) · [nerdctl-variant.tr.md](nerdctl-variant.tr.md) · [cache-guide.tr.md](cache-guide.tr.md) · [evidence.tr.md](evidence.tr.md)
