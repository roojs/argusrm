deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	meson.get_compiler('c').find_library('ocrpc'),
]
localstatedir = get_option('localstatedir')
if not localstatedir.startswith('/')
	localstatedir = get_option('prefix') / localstatedir
endif
paths_vala = configure_file(
	input: 'paths.vala.in',
	output: 'paths.vala',
	configuration: {
		'LOCALSTATEDIR': localstatedir / 'lib' / 'argusrm',
	},
)
sources = files(
	'namespace.vala',
	'Application.vala',
)
sources += paths_vala
executable(
	'argus-controller',
	sources,
	dependencies: deps,
	vala_args: [
		'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	],
	install: true,
)
