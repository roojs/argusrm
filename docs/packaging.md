# Packages and GitHub releases

Argus produces three binary packages from one source tree:

- `argusrm-server` — `/usr/bin/argus` and its systemd service
- `argusrm-agent` — `/usr/bin/argus-agent`, its D-Bus policy, and its
  systemd service
- `argusrm-controller` — `/usr/bin/argus-controller`

`CHANGELOG.md` is the source of truth for release versions, release notes,
and package changelogs. The version being released must also match
`meson.build`.

## Debian packages

Install the build dependencies listed in `debian/control`, including
`libocrpc-dev` and `libocsqlite-dev`, then run:

```sh
chmod +x debian/rules
dpkg-buildpackage -us -uc -b
```

The three `.deb` files are written to the parent directory.

## RPM packages

The RPM build is intended for Fedora and uses the RooJS repository for
`libocrpc-devel` and `libocsqlite-devel`:

```sh
sudo scripts/ci/build-rpm.sh
```

The three non-debug `.rpm` files are written to `artifacts/`.

## GitHub Actions release

The `Release` workflow builds Debian packages, Fedora RPMs, an x86-64
controller AppImage, the Windows agent installer, and an Android arm64 debug
APK. Each family also has a `Release - ...` workflow that can be run manually
without publishing a GitHub Release. The Android job is non-blocking in a
full release while its new Pixiewood build is being proven; its manual
workflow fails normally when the APK cannot be built.

While developing, add notes beneath `## [Unreleased]`. Before a release,
change that heading to the version:

```md
## [0.1.0] - Unreleased
```

Commit that change and make sure the working tree is clean. The human
release command then verifies the changelog, checks it against
`meson.build`, creates annotated `vX.Y.Z` and `vX.Y.Z-packages` tags, and
pushes the branch and tags:

```sh
chmod +x scripts/release.sh scripts/release/*.sh
./scripts/release.sh
```

When `origin` is the private Git server, push the tag there first and let
the mirror send it to GitHub. GitHub Actions starts when GitHub receives the
tag. Debian and RPM files are published on `vX.Y.Z-packages`; AppImage,
Windows, and a successfully built Android APK are published on `vX.Y.Z`.

After a successful release, finalize the changelog on the private source
repository and commit it:

```sh
./scripts/release/finalize-changelog.sh v0.1.0
git add CHANGELOG.md debian/changelog
git commit -m "Finalize changelog for v0.1.0"
git push origin
```

GitHub Actions does not make this commit because the private Git server is
the source of truth and GitHub is its one-way mirror.

## Mirror the private Git server to GitHub

Create an empty GitHub repository (no generated README or license), then
run this in the bare repository on the Git server:

```sh
cd /path/to/argusrm.git
git remote add github git@github.com:OWNER/argusrm.git
git push --mirror github
```

The Git server needs an SSH key accepted by GitHub with write access to the
repository. For later updates, either run the same `git push --mirror
github` command or configure the Git server's push-mirror feature with that
GitHub SSH URL.

`--mirror` makes GitHub exactly match the private repository, including
branches and tags; it also deletes GitHub-only refs. Do not use that command
if work will be committed directly on GitHub.
