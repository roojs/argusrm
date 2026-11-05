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
controller_vala_args = [
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	'--pkg', 'sqlite3', '--pkg', 'ocsqlite',
]
if host_machine.system() == 'linux'
	controller_vala_args += ['-D', 'LINUX', '--pkg', 'posix']
endif
sources = files(
	'namespace.vala',
	'Application.vala',
	'Connection.vala',
	'Pin.vala',
	'Agents.vala',
	'Command.vala',
)
executable(
	'argus-controller',
	sources,
	dependencies: deps,
	c_args: ocsqlite_c_args,
	vala_args: controller_vala_args,
	install: true,
)
command_test = executable(
	'argus-controller-command',
	files('tests/command.vala', 'Command.vala'),
	dependencies: [
		dependency('glib-2.0'),
		dependency('gio-2.0'),
		dependency('gio-unix-2.0'),
		dependency('gee-0.8'),
		dependency('json-glib-1.0'),
		dependency('libsoup-3.0'),
		meson.get_compiler('c').find_library('ocrpc'),
	],
	vala_args: ocrpc_vala_args + [
		'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0',
		'--pkg', 'libsoup-3.0', '--pkg', 'gio-unix-2.0',
	],
	install: false,
)
test('controller-command', command_test, timeout: 10, is_parallel: false)
