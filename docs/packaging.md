# Packages and GitHub releases

Argus Remote Manager produces four binary packages from one source tree:

- `argusrm-server` — `/usr/bin/argusrm-server`, `/usr/bin/argusrm-controller-cli`, its systemd unit, and its SysV init script
- `argusrm-agent` — `/usr/bin/argusrm-agent`, its systemd unit, and its SysV init script
- `argusrm-agent-gtk` — `/usr/bin/argusrm-agent-gtk`, the desktop registration window, and `/etc/xdg/autostart/argusrm-agent-gtk.desktop`
- `argusrm-controller` — `/usr/bin/argusrm-controller`

`CHANGELOG.md` is the source of truth for release versions, release notes,
and package changelogs. The version being released must also match
`meson.build`.

## Debian packages

Install the Debian build dependencies in [Building](build.md), then run:

```sh
chmod +x debian/rules
dpkg-buildpackage -us -uc -b
```

The `.deb` files are written to the parent directory.

## RPM packages

The RPM build is intended for Fedora. `scripts/ci/build-rpm.sh` installs
the Fedora dependencies in [Building](build.md), plus `rpm-build` and
`systemd-rpm-macros`:

```sh
sudo scripts/ci/build-rpm.sh
```

The non-debug `.rpm` files are written to `artifacts/`.

## GitHub Actions release

The `Release` workflow builds Debian packages, Fedora RPMs, an x86-64
controller AppImage, the Windows agent installer, and an Android arm64 debug
APK. Each family also has a `Release - ...` workflow that can be run manually
without publishing a GitHub Release. A failed Android build stops the
release. The manual Android workflow fails the same way when the APK cannot
be built.

While developing, add notes beneath `## [Unreleased]`. Before a release,
change that heading to the version:

```md
## [0.1.0] - Unreleased
```

Commit that change and make sure the working tree is clean. The human
release command then verifies the changelog, checks it against
`meson.build`, creates an annotated `vX.Y.Z` tag, and pushes the branch
and tag:

```sh
chmod +x scripts/release.sh scripts/release/*.sh
./scripts/release.sh
```

When `origin` is the private Git server, push the tag there first and let
the mirror send it to GitHub. GitHub Actions starts when GitHub receives the
tag. Debian packages, Fedora RPMs, the AppImage, Windows installer, and
Android APK are published together on `vX.Y.Z`.

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
