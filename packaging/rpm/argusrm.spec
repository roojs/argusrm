Name: argusrm-server
Version: %{argusrm_version}
Release: 1%{?dist}
Summary: Argus remote management server
License: LGPL-3.0-or-later
URL: https://github.com/roojs/argusrm
Source0: argusrm-%{version}.tar.gz

BuildRequires: meson
%if 0%{?fedora}
BuildRequires: ninja-build
%else
BuildRequires: ninja
%endif
BuildRequires: gcc
BuildRequires: vala
BuildRequires: systemd-rpm-macros
BuildRequires: pkgconfig(glib-2.0)
BuildRequires: pkgconfig(gio-unix-2.0)
BuildRequires: pkgconfig(gee-0.8)
BuildRequires: pkgconfig(json-glib-1.0)
BuildRequires: pkgconfig(libsoup-3.0)
BuildRequires: pkgconfig(gnutls)
BuildRequires: pkgconfig(sqlite3)
BuildRequires: pkgconfig(gtk4)
BuildRequires: pkgconfig(libadwaita-1)
BuildRequires: pkgconfig(avahi-gobject)
BuildRequires: libocrpc-devel
BuildRequires: libocsqlite-devel
Recommends: avahi

%description
Argus enrolls managed machines, provides authenticated downloads, and
coordinates remote management operations.

%package -n argusrm-agent
Summary: Argus remote management agent
Recommends: avahi

%description -n argusrm-agent
The Argus agent runs on a managed Linux machine as a systemd service.

%package -n argusrm-controller
Summary: Argus command-line controller

%description -n argusrm-controller
The Argus command-line controller talks to the local Argus server and opens
agent enrollment windows.

%prep
%autosetup -n argusrm-%{version}

%build
%meson
%meson_build

%install
%meson_install

%post
%systemd_post argusrm-server.service
if [ "$1" -eq 1 ]; then
  systemctl enable --now argusrm-server.service >/dev/null 2>&1 || :
fi

%preun
%systemd_preun argusrm-server.service

%postun
%systemd_postun_with_restart argusrm-server.service

%post -n argusrm-agent
systemctl daemon-reload

%preun -n argusrm-agent
%systemd_preun argusrm-agent.service

%postun -n argusrm-agent
%systemd_postun_with_restart argusrm-agent.service

%files
%license LICENSE
%doc README.md docs/build.md
%{_bindir}/argus
%{_prefix}/lib/systemd/system/argusrm-server.service
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-server

%files -n argusrm-agent
%license LICENSE
%{_bindir}/argus-agent
%{_datadir}/polkit-1/actions/org.roojs.ArgusAgent.register.policy
%{_prefix}/lib/systemd/system/argusrm-agent.service
%{_sysconfdir}/init.d/argusrm-agent
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-agent

%files -n argusrm-controller
%license LICENSE
%{_bindir}/argus-controller

%changelog
