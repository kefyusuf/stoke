# stoke sürüm çıkarma rehberi

Release hattı otomatiktir: `v*` tag'i push etmek kaynak tarball'ı üretir,
sha256 checksum'ları yazar, GitHub Release'i bu asset'lerle oluşturur ve
**build-provenance attestation'ları** ekler (in-toto; GitHub'ın Sigstore
tabanlı OIDC kimliğiyle imzalı — kişisel anahtar yok, CI'da secret yok).
`.intoto.jsonl` paketi release asset'i olarak da yüklenir — OpenSSF
Scorecard'ın Signed-Releases kontrolünün aradığı şey budur.

## Ritüel (maintainer, ~10 dakika)

1. **CHANGELOG**: `[Unreleased]`'ı `[X.Y.Z] - bugün` olarak taşı,
   `[X.Y.Z]: .../releases/tag/vX.Y.Z` link satırını ekle, commit'le.
2. **Tag'le ve ikisini birden push et**:
   ```bash
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```
3. **İzle**: `release` workflow'unu `gh run watch`. Bir dakikadan kısa sürer
   ve şu asset'lerle release'i yayınlar:
   - `stoke-X.Y.Z.tar.gz` (kaynak tarball)
   - `stoke-X.Y.Z.tar.gz.sha256`
   - `attestation.intoto.jsonl` (build provenance)
   - otomatik notlar (`--generate-notes`)
4. **Lokalde sağlama yap**:
   ```bash
   gh release download vX.Y.Z -p "*.tar.gz" -p "*.sha256" -p "*.intoto.jsonl"
   sha256sum -c stoke-X.Y.Z.tar.gz.sha256
   gh attestation verify stoke-X.Y.Z.tar.gz -R kefyusuf/stoke
   ```

## Sürüm disiplini

Semver-benzeri: kit script + şablondan oluşur, dolayısıyla **breaking =
template veya kurulum sözleşmesi değişikliği** (yeniden adlandırılan flag,
değişen default, bozulan cache-ref formatı). Yeni script/dokümantasyon ekleme
minor, düzeltmeler patch'tir.

## Opsiyonel sertleştirme: kişisel imzalı tag

Yukarıdaki attestation'lar *artifact'leri* kapsar. *Tag'in kendisini* de
kişisel olarak imzalamak istersen (yalnızca provenance değil, repo
ele geçirilmesine karşı da savunma):

```bash
# tek seferlik: SSH imza anahtarı en az kurulumlu seçenek
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
# public key'i github.com -> Settings -> SSH keys -> "Signing key" olarak kaydet

git tag -s vX.Y.Z          # imzalar (SSH: -s, user.signingkey'i kullanır)
git push --force origin vX.Y.Z   # force yalnızca henüz indirilmemiş tag'e
```

Alışkanlığı bir sonraki sürümden itibaren edin; yayımlanmış tag'leri
yeniden yazma.

## Scorecard ne görür

- `Signed-Releases`: release üzerindeki `.intoto.jsonl` paketi karşılar
- `Binary-Artifacts`: temiz kalır — release'e yalnızca tarball/checksum
  eklenir, derlenmiş binary asla
