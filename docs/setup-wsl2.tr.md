# Manuel WSL2 + Docker Engine kurulumu

`setup/setup-wsl.ps1` ve `setup/setup-engine.sh`'in otomatik yaptığı işin adım adım
anlatımı. Elle yapmak veya scriptleri debug etmek isteyenler için.

> Neden Docker Desktop değil: [kanıtlar #1](evidence.tr.md#1-docker-desktop-boşta-bile-ağır-wsl2-içinde-engine-çok-daha-hafif).
> Neden ext4, `/mnt/c` değil: [kanıtlar #2](evidence.tr.md#2-mntc-bir-build-hızı-tuzağı-ext4-neredeyse-native).

## 1. WSL2'yi kur

Yönetici PowerShell:

```powershell
wsl --install                 # WSL2 + varsayılan Ubuntu distro, yeniden başlatma gerekir
wsl --set-default-version 2
```

WSL zaten kurulu mu? Distro versiyonunu kontrol et — `VERSION 2` olmalı:

```powershell
wsl -l -v
wsl --set-version <DistroName> 2
```

WSL1 olarak çalışan distroda **Docker Engine çalışmaz** — v2'ye çevirmek zorunludur.

## 2. VM'i `%UserProfile%\.wslconfig` ile sınırla

`setup/.wslconfig.template` dosyasını `%UserProfile%\.wslconfig`'e kopyala ve ayarla:

```ini
[wsl2]
memory=6GB        # tüm VM için sert üst sınır (Task Manager'da VMMEM olarak görünür)
processors=4      # VM'in göreceği mantıksal çekirdek
swap=2GB

[experimental]
autoMemoryReclaim=gradual   # boşta önbellek belleğini Windows'a geri ver (WSL 2.0+)
sparseVhd=true              # silme sonrası ext4 disk dosyasını küçült (WSL 2.0+)
```

`wsl --shutdown` ile uygula (sonraki açılışta devreye girer). Referans:
[Microsoft — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

Boyutlama kuralı: `memory` ≈ host RAM'inin 1/3–1/2'si; kalanı Windows ve tarayıcıya bırak
— asıl bellek yiyenler genelde onlar.

## 3. Kaynakları distro içinde tut

```bash
mkdir -p ~/work && cd ~/work
git clone <projen>
```

- Düzenleme: VS Code → *Remote-WSL: Connect* (veya JetBrains Gateway). Editor küçük bir
  sunucuyu WSL içinde çalıştırır; dosyalar fiziksel olarak ext4'te dururken sen
  Windows'ta alıştığın gibi çalışırsın.
- **Asla `/mnt/c/...` üzerinden build etme** — `pwd` ile doğrula; `/mnt/` ile başlıyorsa
  klonu taşı.

## 4. systemd'yi aç (docker servisi için gerekli)

Distro içinde, `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Sonra Windows'tan bir kez `wsl --shutdown`. (Ubuntu 22.04+ bunu açık gönderir.)

## 5. Docker Engine'i kur

`setup/setup-engine.sh`'i çalıştır, ya da elle:

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
sudo usermod -aG docker "$USER"   # sonrasında çık-gir yap veya `newgrp docker`
```

**Debian**'da her iki URL'de `linux/ubuntu` yerine `linux/debian` yaz (repo
anahtarı ve apt kaynağı distro başına ayrıdır). Resmî kaynak:
[Docker — Ubuntu'ya kurulum](https://docs.docker.com/engine/install/ubuntu/).

## 6. Sağlık kontrolü

```bash
docker version          # client + server, sudo'suz
docker buildx version   # BuildKit frontend
docker run --rm hello-world
```

`docker version` sudo istiyorsa grup adımını atlamışsındır — WSL'den çık-gir yap.

## Günlük kullanım

| Görev | Komut |
|---|---|
| İşe başla | terminal aç → distro otomatik başlar; docker systemd servisi olarak çalışır |
| VM ayak izine bak | Task Manager → `VMMEM` (en fazla `memory=` sınırında durmalı) |
| Tam sıfırlama | PowerShell'den `wsl --shutdown` |
| Büyük temizlik sonrası disk boşalt | `wsl --manage <DistroName> --set-sparse true` (veya `sparseVhd`'ye güven) |

Devamı: paylaşımlı build cache'i kurmak için [cache-guide.tr.md](cache-guide.tr.md).
