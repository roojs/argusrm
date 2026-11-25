# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

gnome = import('gnome')
server_resources = gnome.compile_resources(
	'argus-server-resources',
	'resources/argusrm-server.gresource.xml',
	source_dir: 'resources',
	c_name: 'argus_server_resources',
)

deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gnutls'),
	dependency('libgit2-glib-1.0'),
	dependency('libnftables'),
	meson.get_compiler('c').find_library('ocrpc'),
]
deps += shared_server_dep
libnl = dependency('libnl-3.0')
nl_route = meson.get_compiler('c').find_library('nl-route-3', required: false)
if not nl_route.found()
	nl_route = declare_dependency(link_args: ['-l:libnl-route-3.so.200'])
endif
deps += [libnl, nl_route]
server_vala_args = [
	'--vapidir', meson.current_source_dir() / 'vapi',
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	'--pkg', 'gnutls', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
	'--pkg', 'libgit2-glib-1.0', '--pkg', 'posix', '--pkg', 'linux',
	'-D', 'LINUX',
]
sources = files(
	'namespace.vala',
	'Net/namespace.vala',
	'Net/SslListen.vala',
	'Net/SslConnection.vala',
	'Net/Download.vala',
	'Net/NFTables.vala',
	'Net/Address.vala',
	'Net/Interfaces.vala',
	'Application.vala',
	'Initialize.vala',
	'GitHub.vala',
	'Offering/namespace.vala',
	'Offering/Network.vala',
	'Offering/Certificate.vala',
	'Offering/Rpc.vala',
	'Registration.vala',
	'OSQuery.vala',
	'OsUpdate.vala',
	'Command.vala',
	'SQT/namespace.vala',
	'SQT/Script.vala',
	'SQT/ScriptRepository.vala',
	'SQT/Distributable.vala',
	'SQV/namespace.vala',
	'SQV/DistributeMachine.vala',
	'SQV/PackageMachine.vala',
	'SQV/AptDepends.vala',
	'SQT/Scheduler.vala',
	'SQT/Task.vala',
	'SQT/Agent.vala',
	'Git/Callbacks.vala',
	'Win/namespace.vala',
	'Win/Installer.vala',
	'Apt/namespace.vala',
	'Apt/CatalogImport.vala',
	'Apt/CatalogRefresh.vala',
	'Daemon.vala',
	'Rdp/Seat.vala',
	'Rdp/Relay.vala',
)
executable(
	'argusrm-server',
	sources,
	server_resources,
	files('main.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: true,
)
if host_machine.system() == 'linux'
	register_policy = configure_file(
		input: 'linux/org.roojs.ArgusServer.register.policy.in',
		output: 'org.roojs.ArgusServer.register.policy',
		configuration: {
			'SERVER_EXECUTABLE': server_executable,
		},
	)
	install_data(
		register_policy,
		install_dir: get_option('datadir') / 'polkit-1' / 'actions',
	)
endif
allowlist_test = executable(
	'argus-allowlist-test',
	sources,
	files('tests/allowlist.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
test('allowlist', allowlist_test, timeout: 30)
packages_test = executable(
	'argus-packages-test',
	sources,
	files('tests/packages.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
test('packages', packages_test, timeout: 30)
apt_catalog_test = executable(
	'argus-apt-catalog-test',
	files(
		'Apt/namespace.vala',
		'Apt/CatalogImport.vala',
		'tests/apt-catalog.vala',
	),
	dependencies: [
		dependency('glib-2.0'),
		dependency('gobject-2.0'),
		dependency('gio-2.0'),
		dependency('gee-0.8'),
		dependency('libsoup-3.0'),
		shared_server_dep,
		ocsqlite_dep,
	],
	c_args: ocsqlite_c_args,
	vala_args: [
		'--vapidir', meson.current_source_dir() / 'vapi',
		'--pkg', 'gee-0.8', '--pkg', 'libsoup-3.0',
		'--pkg', 'ocrpc', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
	],
	install: false,
)
test('apt-catalog', apt_catalog_test, timeout: 300)
apt_url_sources_test = executable(
	'argus-apt-url-sources-test',
	sources,
	files('tests/apt-url-sources.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
test('apt-url-sources', apt_url_sources_test, timeout: 30)
apt_explicit_test = executable(
	'argus-apt-explicit-test',
	files('tests/apt-explicit-install.vala'),
	dependencies: [
		dependency('glib-2.0'),
		dependency('gobject-2.0'),
		dependency('gio-2.0'),
		dependency('gee-0.8'),
		shared_server_dep,
		ocsqlite_dep,
	],
	vala_args: [
		'--pkg', 'gee-0.8', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
		'--pkg', 'ocrpc',
	],
	install: false,
)
test('apt-explicit-install', apt_explicit_test, timeout: 30)
apt_depends_test = executable(
	'argus-apt-depends-test',
	sources,
	files('tests/apt-depends.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
test('apt-depends', apt_depends_test, timeout: 30)
if host_machine.system() == 'linux'
	registration_certificate_test = executable(
		'argus-registration-certificate',
		sources,
		files('tests/registration-certificate.vala'),
		dependencies: deps + [shared_register_dep],
		c_args: ocsqlite_c_args,
		export_dynamic: true,
		vala_args: server_vala_args,
		install: false,
	)
	test(
		'registration-certificate',
		registration_certificate_test,
		timeout: 30,
		is_parallel: false,
	)
endif
offering_registration_sources = files(
	'namespace.vala',
	'Net/namespace.vala',
	'Net/SslListen.vala',
	'Net/SslConnection.vala',
	'Net/NFTables.vala',
	'Net/Address.vala',
	'Net/Interfaces.vala',
	'Net/Download.vala',
	'Offering/namespace.vala',
	'Offering/Network.vala',
	'Offering/Certificate.vala',
	'Offering/Rpc.vala',
	'SQT/Scheduler.vala',
	'SQT/Task.vala',
	'SQT/Agent.vala',
	'Command.vala',
	'Daemon.vala',
	# Stub Application. Left out of valadoc; the real class is already documented.
	'tests/offering-test-application.vala',
	'tests/offering-registration-server.vala',
	'tests/offering-registration.vala',
)
offering_registration_deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gnutls'),
	dependency('libnftables'),
	meson.get_compiler('c').find_library('ocrpc'),
	libnl,
	nl_route,
] + [shared_server_dep]
offering_registration_test = executable(
	'argus-offering-registration',
	offering_registration_sources,
	dependencies: offering_registration_deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
test(
	'offering-registration',
	offering_registration_test,
	timeout: 60,
	is_parallel: false,
)
registration_local_login_test = executable(
	'argus-registration-local-login',
	sources,
	files('tests/registration-local-login.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: false,
)
server_for_local_login = join_paths(meson.project_build_root(), 'server', 'argusrm-server')
test(
	'registration-local-login',
	registration_local_login_test,
	args: [server_for_local_login],
	timeout: 30,
	is_parallel: false,
)
rdp_start_test = executable(
	'argus-rdp-start-test',
	files('Rdp/Relay.vala', 'Rdp/Seat.vala', 'tests/rdp-start.vala'),
	dependencies: shared_deps + [shared_server_dep],
	c_args: ocsqlite_c_args,
	vala_args: shared_vala_args + [
		'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
		'--pkg', 'gio-2.0', '--pkg', 'posix',
	],
	install: false,
)
test('rdp-start', rdp_start_test, args: ['prove'], timeout: 30)
executable(
	'argus-nftables-test',
	files('tests/nftables.vala', 'Net/NFTables.vala'),
	dependencies: [
		dependency('glib-2.0'),
		dependency('gobject-2.0'),
		dependency('gio-2.0'),
		dependency('gee-0.8'),
		dependency('libnftables'),
	],
	vala_args: [
		'--vapidir', meson.current_source_dir() / 'vapi',
		'--pkg', 'gee-0.8', '--pkg', 'gio-2.0', '--pkg', 'posix',
	],
	install: false,
)
server_sources = sources
server_deps = deps
