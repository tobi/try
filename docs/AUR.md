# AUR packaging plan (`try-cli`)

Keep the user-facing install command as:

```bash
yay -S try-cli
# or
paru -S try-cli
```

Do not rename the package. Do not fight the existing community `try-cli-bin` package.

## Current AUR state

| Package | Version | Maintainer | Notes |
| --- | --- | --- | --- |
| [`try-cli`](https://aur.archlinux.org/packages/try-cli) | **1.5.3-1** | tobilu | 0 votes. Upstream is the C rewrite at [tobi/try-cli](https://github.com/tobi/try-cli). |
| [`try-cli-bin`](https://aur.archlinux.org/packages/try-cli-bin) | 1.5.3-2 | Dominiquini (tobilu co-maintainer) | Separate community binary package. Leave it alone. |

This repo takes over **`try-cli` only**. Same pkgname, same `provides=('try')` / `conflicts=('try')`, so `yay -S try-cli` keeps working. Upstream URL becomes [tobi/try](https://github.com/tobi/try). The payload is the Spinel-compiled native `dist/try` binary, not the old C rewrite (that repo is the historical snapshot).

## Why a prebuilt binary, not a source PKGBUILD

AUR cannot depend on unpublished Spinel. `make native` emits `dist/try.c` and links `libspinel_rt.a`; neither Spinel nor that runtime is on AUR. Compiling on the AUR builder is not possible today.

The PKGBUILD therefore fetches a GitHub Release asset:

- asset name: `try-linux-x86_64.tar.gz`
- contents: a `try` binary at the tarball root
- URL: `https://github.com/tobi/try/releases/download/v$pkgver/try-linux-x86_64.tar.gz`

Native links `glibc`, `libm`, and `libcrypt` (`libxcrypt` on Arch). `sha256sums` is `SKIP` in git; CI runs `updpkgsums` before publish.

Building the native binary yourself remains optional (`make native`). The AUR package is the prebuilt path for Arch users.

## What CI does

`.github/workflows/release.yml` on a version tag:

1. **`release`** — existing gem push (RubyGems trusted publishing). Must keep working.
2. **`native-release`** — optional. If `spinel` is on the runner, builds `dist/try` and uploads `try-linux-x86_64.tar.gz` via `softprops/action-gh-release`. Spinel is **not** on GitHub Actions by default; the job is `continue-on-error` and must not fail the gem release. Until Spinel is available, upload that tarball to the GitHub release by hand.
3. **`aur-publish`** — copied from try-cli: Arch container, `updpkgsums`, `KSXGitHub/github-actions-deploy-aur@v4.1.1`, pkgname `try-cli`, environment `OpenSource`.

## To actually push to AUR

Until the secrets exist on **this** repo, do not pretend AUR was updated. The live package stays 1.5.3-1.

1. Copy secrets from **tobi/try-cli**'s `OpenSource` GitHub environment onto **tobi/try**'s `OpenSource` environment:
   - `AUR_USERNAME`
   - `AUR_EMAIL`
   - `AUR_SSH_PRIVATE_KEY`
   tobi/try currently has no `OpenSource` env (it has Rubygems, github-pages, copilot). Create `OpenSource` and paste those three secrets.
2. Build `dist/try` locally (`make native`) and upload `try-linux-x86_64.tar.gz` (binary named `try` at the tarball root) to the GitHub release for `vX.Y.Z`.
3. Tag `vX.Y.Z` (or re-run the `aur-publish` job on that tag). CI updates `pkgver`, runs `updpkgsums`, and force-pushes the AUR repo.

Local helper: `make update-pkg` (perl `pkgver` from `VERSION`, then `makepkg --printsrcinfo`).
