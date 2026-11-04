deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gnutls'),
	meson.get_compiler('c').find_library('ocrpc'),
]
deps += shared_dep
server_vala_args = [
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	'--pkg', 'gnutls', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
]
sources = files(
	'namespace.vala',
	'Application.vala',
	'Initialize.vala',
	'GitHub.vala',
	'SslListen.vala',
	'SslConnection.vala',
	'Agent.vala',
	'OSQuery.vala',
	'Command.vala',
	'Daemon.vala',
	'Download.vala',
)
executable(
	'argus',
	sources,
	dependencies: deps,
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: true,
)
