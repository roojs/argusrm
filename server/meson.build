# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

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
deps += shared_dep
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
	'--pkg', 'libgit2-glib-1.0', '--pkg', 'posix',
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
	'Agent.vala',
	'Registration.vala',
	'OSQuery.vala',
	'Command.vala',
	'SQT/Script.vala',
	'SQT/ScriptRepository.vala',
	'SQT/Scheduler.vala',
	'SQT/Task.vala',
	'Git/Callbacks.vala',
	'Daemon.vala',
)
executable(
	'argus',
	sources,
	files('main.vala'),
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: true,
)
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
