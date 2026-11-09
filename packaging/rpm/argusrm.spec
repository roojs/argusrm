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
coordinates remote management operations. The package includes
argusrm-controller-cli, the command-line controller that opens registration
on the server. That command does not use GTK.

%package -n argusrm-agent
Summary: Argus Remote Manager command-line agent
Obsoletes: argusrm-agent-cli
Recommends: avahi

%description -n argusrm-agent
The command-line Argus Remote Manager agent for a managed Linux machine.
The command is argusrm-agent. It does not use GTK. This is the package
to install on a server.

%package -n argusrm-agent-gtk
Summary: Argus Remote Manager agent with a registration window
Requires: argusrm-agent = %{version}-%{release}
Recommends: avahi

%description -n argusrm-agent-gtk
The argusrm-agent-gtk command, which opens a desktop registration window
and starts at login. The service is the command-line agent. Install
argusrm-agent alone on a machine without a desktop.

%package -n argusrm-controller
Summary: Argus Remote Manager desktop controller

%description -n argusrm-controller
The Argus Remote Manager desktop controller enrolls with a server and
opens the management window. Registration on the server uses
argusrm-controller-cli from the server package.

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

%post -n argusrm-agent
systemctl daemon-reload

%preun -n argusrm-agent
%systemd_preun argusrm-agent.service

%postun -n argusrm-agent
%systemd_postun_with_restart argusrm-agent.service

%files
%license LICENSE
%doc README.md docs/build.md
%{_bindir}/argusrm-server
%{_bindir}/argusrm-controller-cli
%{_prefix}/lib/systemd/system/argusrm-server.service
%{_sysconfdir}/init.d/argusrm-server
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-server

%files -n argusrm-agent
%license LICENSE
%{_bindir}/argusrm-agent
%{_prefix}/lib/systemd/system/argusrm-agent.service
%{_datadir}/dbus-1/system.d/org.roojs.ArgusAgent.conf
%{_sysconfdir}/init.d/argusrm-agent
%config(noreplace) %{_sysconfdir}/logrotate.d/argusrm-agent

%files -n argusrm-agent-gtk
%license LICENSE
%{_bindir}/argusrm-agent-gtk
%{_datadir}/polkit-1/actions/org.roojs.ArgusAgent.register.policy
%{_sysconfdir}/xdg/autostart/argusrm-agent-gtk.desktop

%files -n argusrm-controller
%license LICENSE
%{_bindir}/argusrm-controller
%{_datadir}/polkit-1/actions/org.roojs.ArgusController.register.policy

%changelog
