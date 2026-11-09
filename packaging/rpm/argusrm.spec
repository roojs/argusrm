Name: argusrm-server
Version: %{argusrm_version}
Release: 1%{?dist}
Summary: Argus Remote Manager server
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
BuildRequires: pkgconfig(libsecret-1)
BuildRequires: pkgconfig(avahi-gobject)
BuildRequires: pkgconfig(avahi-client)
BuildRequires: pkgconfig(libgit2-glib-1.0)
BuildRequires: pkgconfig(libnftables)
BuildRequires: pkgconfig(libnl-3.0)
BuildRequires: libocrpc-devel
BuildRequires: libocsqlite-devel
Recommends: avahi

%description
Argus Remote Manager enrolls managed machines, provides authenticated downloads, and
coordinates remote management operations.

%package -n argusrm-agent-cli
Summary: Argus Remote Manager command-line agent
Obsoletes: argusrm-agent < 0.1.1-1
Provides: argusrm-agent = %{version}-%{release}
Recommends: avahi

%description -n argusrm-agent-cli
The command-line Argus Remote Manager agent for a managed Linux machine.
The command is argus-agent-cli. It does not use GTK. This is the package
to install on a server.

%package -n argusrm-agent-gtk
Summary: Argus Remote Manager agent with a registration window
Requires: argusrm-agent-cli = %{version}-%{release}
Recommends: avahi

%description -n argusrm-agent-gtk
The argus-agent command, which opens a desktop registration window.
The service is the command-line agent. Install argusrm-agent-cli alone
on a machine without a desktop.

%package -n argusrm-controller
Summary: Argus Remote Manager command-line controller

%description -n argusrm-controller
The Argus Remote Manager command-line controller talks to the local
Argus Remote Manager server and opens agent enrollment windows.

%prep
%autosetup -n argusrm-%{version}

%build
%meson -Ddocs=false
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

%post -n argusrm-agent-cli
systemctl daemon-reload

%preun -n argusrm-agent-cli
%systemd_preun argusrm-agent.service

%postun -n argusrm-agent-cli
%systemd_postun_with_restart argusrm-agent.service

%files
%license LICENSE
%doc README.md docs/build.md
%{_bindir}/argus
%{_prefix}/lib/systemd/system/argusrm-server.service
%{_sysconfdir}/init.d/argusrm-server
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-server

%files -n argusrm-agent-cli
%license LICENSE
%{_bindir}/argus-agent-cli
%{_prefix}/lib/systemd/system/argusrm-agent.service
%{_sysconfdir}/init.d/argusrm-agent
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-agent

%files -n argusrm-agent-gtk
%license LICENSE
%{_bindir}/argus-agent
%{_datadir}/polkit-1/actions/org.roojs.ArgusAgent.register.policy

%files -n argusrm-controller
%license LICENSE
%{_bindir}/argus-controller
%{_datadir}/polkit-1/actions/org.roojs.ArgusController.register.policy

%changelog
