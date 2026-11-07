# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gtk4'),
	dependency('libadwaita-1'),
	ocrpc_dep,
]
deps += shared_dep
controller_vala_args = ocrpc_vala_args + ocsqlite_vala_args + [
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
	'--pkg', 'sqlite3',
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
]
if host_machine.system() == 'linux'
	controller_vala_args += ['-D', 'LINUX', '--pkg', 'posix', '--pkg', 'libsecret-1']
	deps += dependency('libsecret-1')
	register_policy = configure_file(
		input: 'linux/org.roojs.ArgusController.register.policy.in',
		output: 'org.roojs.ArgusController.register.policy',
		configuration: {
			'CONTROLLER_EXECUTABLE': bindir / 'argus-controller',
		},
	)
	install_data(
		register_policy,
		install_dir: get_option('datadir') / 'polkit-1' / 'actions',
	)
endif
sources = files(
	'namespace.vala',
	'Application.vala',
	'Connection.vala',
	'Bootstrap.vala',
	'PairingDialog.vala',
	'Window.vala',
	'Pin.vala',
	'Agents.vala',
	'Command.vala',
)
if host_machine.system() == 'android'
	executable(
		'argus-controller',
		sources,
		files('main.vala'),
		dependencies: deps,
		c_args: ocsqlite_c_args,
		vala_args: controller_vala_args,
		android_exe_type: 'application',
		install: true,
	)
else
	executable(
		'argus-controller',
		sources,
		files('main.vala'),
		dependencies: deps,
		c_args: ocsqlite_c_args,
		vala_args: controller_vala_args,
		install: true,
	)
endif
if host_machine.system() == 'linux'
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
			dependency('gtk4'),
			dependency('libadwaita-1'),
			dependency('sqlite3'),
			meson.get_compiler('c').find_library('ocrpc'),
			shared_dep,
		],
		c_args: ocsqlite_c_args,
		vala_args: ocrpc_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0',
			'--pkg', 'libsoup-3.0', '--pkg', 'gio-unix-2.0',
			'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
			'--pkg', 'sqlite3', '--pkg', 'ocsqlite',
		],
		install: false,
	)
	test('controller-command', command_test, timeout: 10, is_parallel: false)
endif
