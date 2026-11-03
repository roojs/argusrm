# Packages and GitHub releases

Argus produces three binary packages from one source tree:

- `argusrm-server` — `/usr/bin/argus` and its systemd service
- `argusrm-agent` — `/usr/bin/argus-agent`, its D-Bus policy, and its
  systemd service
- `argusrm-controller` — `/usr/bin/argus-controller`

The package version comes from `meson.build`. Keep `debian/changelog` at the
same version for local builds. A `vX.Y.Z` Git tag overrides both package
versions in GitHub Actions.

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

The `Packages` workflow can be run manually from the Actions page to test
both package builds. To build all six packages and attach them to a GitHub
Release, push a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

When `origin` is the private Git server, push the tag there first and let
the mirror send it to GitHub. GitHub Actions starts when GitHub receives the
tag.

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
