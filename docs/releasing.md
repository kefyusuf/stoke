# Releasing stoke

The release pipeline is automated: pushing a `v*` tag builds the source
tarball, writes sha256 checksums, creates the GitHub Release with those
assets, and attaches **build-provenance attestations** (in-toto, signed by
GitHub's Sigstore-backed OIDC identity - no personal key to manage, no
secrets in CI). The `.intoto.jsonl` bundle is uploaded as a release asset
too, which is what OpenSSF Scorecard's Signed-Releases check recognizes.

## The ritual (maintainer, ~10 minutes)

1. **CHANGELOG**: move `[Unreleased]` to `[X.Y.Z] - today`, add the
   `[X.Y.Z]: .../releases/tag/vX.Y.Z` link line, commit.
2. **Tag and push both**:
   ```bash
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```
3. **Watch**: `gh run watch` on the `release` workflow. It finishes in
   under a minute and publishes the release with:
   - `stoke-X.Y.Z.tar.gz` (source tarball)
   - `stoke-X.Y.Z.tar.gz.sha256`
   - `attestation.intoto.jsonl` (build provenance)
   - auto-generated notes (`--generate-notes`)
4. **Sanity-check locally**:
   ```bash
   gh release download vX.Y.Z -p "*.tar.gz" -p "*.sha256" -p "*.intoto.jsonl"
   sha256sum -c stoke-X.Y.Z.tar.gz.sha256
   gh attestation verify stoke-X.Y.Z.tar.gz -R kefyusuf/stoke
   ```

## Version discipline

Semver-ish: the kit is scripts + templates, so **breaking = a template or
setup contract change** (a flag renamed, a default changed, a cache-ref
format altered). Additions of new scripts/docs are minor. Fixes are patch.

## Optional hardening: a personally signed tag

The attestations above cover *artifacts*. If you also want the *tag itself*
personally signed (defense against repo compromise, not just provenance):

```bash
# one-time: an SSH signing key is the least-setup option
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
# register the public key at github.com -> Settings -> SSH keys -> "Signing key"

git tag -s vX.Y.Z          # actually signs (SSH: -s uses user.signingkey)
git push --force origin vX.Y.Z   # only ever force on a not-yet-downloaded tag
```

Establish the habit from the next release on; do not rewrite already
published tags.

## What Scorecard sees

- `Signed-Releases`: satisfied by the `.intoto.jsonl` bundle on the release
- `Binary-Artifacts`: stays clean - only tarballs/checksums are attached,
  never built binaries
