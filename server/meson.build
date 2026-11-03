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
	'ClientCert.vala',
	'Daemon.vala',
	'Download.vala',
)
sources += paths_vala
executable(
	'argus',
	sources,
	dependencies: deps,
	c_args: ocsqlite_c_args,
	vala_args: [
		'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
		'--pkg', 'gnutls', '--pkg', 'sqlite3', '--pkg', 'ocsqlite',
	],
	install: true,
)
