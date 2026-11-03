fs = import('fs')
cc = meson.get_compiler('c')
ocsqlite_c_args = []
# libocsqlite.so is installed without ocsqlite.h. The header is the one valac writes in the OLLMchat build.
if not cc.has_header('ocsqlite.h')
	ocsqlite_header_dir = meson.project_source_root() / '..' / 'OLLMchat' / 'build' / 'libocsqlite'
	if not fs.exists(ocsqlite_header_dir / 'ocsqlite.h')
		error('ocsqlite.h is not installed')
	endif
	ocsqlite_c_args = ['-I' + ocsqlite_header_dir]
endif
deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gnutls'),
	dependency('sqlite3'),
	meson.get_compiler('c').find_library('ocrpc'),
	meson.get_compiler('c').find_library('ocsqlite'),
]
server_vala_args = [
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	'--pkg', 'gnutls', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
]
server_osquery_lib = static_library(
	'argus-server-osquery',
	shared_osquery_sources,
	dependencies: deps,
	c_args: ocsqlite_c_args,
	vala_args: server_vala_args,
	vala_header: 'argus-server-osquery.h',
	vala_vapi: 'argus-server-osquery.vapi',
)
server_osquery_dep = declare_dependency(
	link_with: server_osquery_lib,
	dependencies: deps,
	include_directories: include_directories('.'),
)
sysconfdir = get_option('sysconfdir')
if not sysconfdir.startswith('/')
	sysconfdir = get_option('prefix') / sysconfdir
endif
localstatedir = get_option('localstatedir')
if not localstatedir.startswith('/')
	localstatedir = get_option('prefix') / localstatedir
endif
paths_vala = configure_file(
	input: 'paths.vala.in',
	output: 'paths.vala',
	configuration: {
		'SYSCONFDIR': sysconfdir / 'argusrm',
		'LOCALSTATEDIR': localstatedir / 'lib' / 'argusrm',
		'SOCKET_PORT': get_option('socket_port').to_string(),
		'DOWNLOAD_PORT': get_option('download_port').to_string(),
	},
)
sources = files(
	'namespace.vala',
	'Application.vala',
	'Initialize.vala',
	'GitHub.vala',
	'SslListen.vala',
	'SslConnection.vala',
	'Agent.vala',
	'OSQuery.vala',
	'Daemon.vala',
	'Download.vala',
)
sources += paths_vala
executable(
	'argus',
	sources,
	dependencies: [deps, server_osquery_dep],
	c_args: ocsqlite_c_args,
	export_dynamic: true,
	vala_args: server_vala_args,
	install: true,
)
