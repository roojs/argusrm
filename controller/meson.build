deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	meson.get_compiler('c').find_library('ocrpc'),
]
deps += shared_dep
sources = files(
	'namespace.vala',
	'Application.vala',
	'Pin.vala',
	'Agents.vala',
	'Command.vala',
)
executable(
	'argus-controller',
	sources,
	dependencies: deps,
	c_args: ocsqlite_c_args,
	vala_args: [
		'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
		'--pkg', 'sqlite3', '--pkg', 'ocsqlite',
	],
	install: true,
)
