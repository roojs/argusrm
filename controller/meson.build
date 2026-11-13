# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

gnome = import('gnome')
controller_resources = gnome.compile_resources(
	'argus-controller-resources',
	'resources/argusrm.gresource.xml',
	source_dir: 'resources',
	c_name: 'argus_controller_resources',
)
controller_icon_resources = gnome.compile_resources(
	'argus-controller-icons',
	meson.project_source_root() / 'pixmaps' / 'argus-icons.gresource.xml',
	source_dir: meson.project_source_root(),
	c_name: 'argus_controller_icons',
)

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
	'--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
	'--pkg', 'sqlite3',
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
]
# Android passes gee-0.8.vapi as a source via dependency('gee-0.8').
# --pkg=gee-0.8 looks for a host package and fails in the Pixiewood build.
if host_machine.system() != 'android'
	controller_vala_args += ['--pkg', 'gee-0.8']
endif
if host_machine.system() == 'linux'
	controller_vala_args += ['-D', 'LINUX', '--pkg', 'posix', '--pkg', 'libsecret-1']
	deps += dependency('libsecret-1')
	register_policy = configure_file(
		input: 'linux/org.roojs.ArgusController.register.policy.in',
		output: 'org.roojs.ArgusController.register.policy',
		configuration: {
			'CONTROLLER_EXECUTABLE': bindir / 'argusrm-controller',
		},
	)
	install_data(
		register_policy,
		install_dir: get_option('datadir') / 'polkit-1' / 'actions',
	)
endif
sources = files(
	'namespace.vala',
	'About.vala',
	'Application.vala',
	'Command.vala',
	'Connection.vala',
	'dialog/Bootstrap.vala',
	'dialog/Pairing.vala',
	'dialog/Repository.vala',
	'store/Agent.vala',
	'store/SystemInfo.vala',
	'store/DebPackages.vala',
	'store/RpmPackages.vala',
	'store/Programs.vala',
	'store/Repository.vala',
	'filter/namespace.vala',
	'filter/SystemInfo.vala',
	'filter/DebPackages.vala',
	'filter/Tasks.vala',
	'tab/Agent.vala',
	'tab/Assets.vala',
	'tab/Asset/namespace.vala',
	'tab/Asset/Machine/namespace.vala',
	'tab/Asset/Machine/DebPackages.vala',
	'tab/Asset/Machine/RpmPackages.vala',
	'tab/Asset/Machine/Programs.vala',
	'tab/Asset/Machine/Detail.vala',
	'tab/Asset/SystemInfo.vala',
	'tab/Asset/Software.vala',
	'tab/Asset/DebPackages.vala',
	'tab/Asset/RpmPackages.vala',
	'tab/Asset/Programs.vala',
	'tab/Base.vala',
	'tab/Dashboard.vala',
	'tab/Repository.vala',
	'tab/Settings.vala',
	'tab/Tasks.vala',
	'TabList.vala',
	'Window.vala',
)
if host_machine.system() == 'windows'
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
endif
if host_machine.system() == 'android'
	executable(
		'argus-controller',
		sources,
		controller_resources,
		controller_icon_resources,
		files('main.vala'),
		dependencies: deps,
		c_args: ocsqlite_c_args,
		vala_args: controller_vala_args,
		android_exe_type: 'application',
		install: true,
	)
else
	executable(
		'argusrm-controller',
		sources,
		controller_resources,
		controller_icon_resources,
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
	# Command-line controller for the server package. No GTK.
	# Left out of valadoc because the type name is already documented.
	executable(
		'argusrm-controller-cli',
		files(
			'namespace.vala',
			'cli/Application.vala',
			'cli/main.vala',
			'cli/Pin.vala',
			'Agents.vala',
			'Command.vala',
		),
		dependencies: [
			shared_cli_dep,
			dependency('gio-unix-2.0'),
		],
		c_args: ocsqlite_c_args,
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'libsoup-3.0',
			'--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
			'--pkg', 'gio-unix-2.0', '--pkg', 'posix',
			'-D', 'LINUX',
		],
		install: true,
	)
endif
