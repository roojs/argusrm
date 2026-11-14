# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

deps = [
	shared_dep,
	dependency('gtk4'),
	dependency('libadwaita-1'),
]
sources = files(
	'namespace.vala',
	'Application.vala',
	'Download.vala',
)
vala_args = ocrpc_vala_args + ocsqlite_vala_args + [
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1', '--pkg', 'libsoup-3.0',
	'--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
]
# Android passes gee-0.8.vapi as a source via dependency('gee-0.8').
# --pkg=gee-0.8 looks for a host package and fails in the Pixiewood build.
if host_machine.system() != 'android'
	vala_args += ['--pkg', 'gee-0.8']
endif
c_args = ocsqlite_c_args

if host_machine.system() == 'linux'
	deps += dependency('gio-unix-2.0')
	register_policy = configure_file(
		input: 'linux/org.roojs.ArgusAgent.register.policy.in',
		output: 'org.roojs.ArgusAgent.register.policy',
		configuration: {
			'AGENT_EXECUTABLE': agent_executable,
		},
	)
	sources += files(
		'OSQuery/Initialize.vala',
		'OSQuery/Execute.vala',
		'OSQuery/LoggedInUsers.vala',
		'OSQuery/Package.vala',
		'OSQuery/DebPackages.vala',
		'OSQuery/RpmPackages.vala',
		'OSQuery/Programs.vala',
		'linux/Application.vala',
		'linux/ServiceManager.vala',
		'linux/Command.vala',
		'linux/PackageMonitor.vala',
		'linux/UserMonitor.vala',
		'linux/UpdatesAvailable.vala',
		'linux/main.vala',
	)
	vala_args += [
		'-D', 'LINUX', '--pkg', 'gio-unix-2.0', '--pkg', 'posix',
	]
	install_data(
		register_policy,
		install_dir: get_option('datadir') / 'polkit-1' / 'actions',
	)
endif

if host_machine.system() == 'windows'
	deps += meson.get_compiler('c').find_library('advapi32')
	deps += meson.get_compiler('c').find_library('user32')
	deps += meson.get_compiler('c').find_library('shell32')
	deps += meson.get_compiler('c').find_library('psapi')
	deps += meson.get_compiler('c').find_library('wtsapi32')
	deps += meson.get_compiler('c').find_library('wevtapi')
	sources += files(
		'OSQuery/Initialize.vala',
		'OSQuery/Execute.vala',
		'OSQuery/Package.vala',
		'OSQuery/DebPackages.vala',
		'OSQuery/RpmPackages.vala',
		'OSQuery/Programs.vala',
		'Win32/Service.vala',
		'Win32/register-pipe.c',
		'Win32/tray/Tray.vala',
		'Win32/Command.vala',
		'Win32/PackageMonitor.vala',
		'Win32/UserMonitor.vala',
		'Win32/UpdatesAvailable.vala',
		'Win32/main.vala',
	)
	vala_args += [
		'--vapidir', meson.current_source_dir() / 'Win32', '--pkg', 'win32',
		'-D', 'WINDOWS',
	]
	c_args += [
		'-D_WIN32_WINNT=0x0601',
		'-D_WIN32_IE=0x0601',
		'-I' + meson.current_source_dir() / 'Win32',
	]
	win_mod = import('windows')
	sources += win_mod.compile_resources(
		files('../packaging/windows/argusrm.rc'),
		include_directories: include_directories('../packaging/windows'),
	)
endif

if host_machine.system() == 'android'
	# A phone can register and then sends no inventory. osquery publishes
	# no Android package. The agent is not built until a phone can report.
	message('Android agent is not built')
else
	installed_name = 'argus-agent'
	if host_machine.system() == 'linux'
		installed_name = 'argusrm-agent-gtk'
	endif
	executable(
		installed_name,
		sources,
		dependencies: deps,
		export_dynamic: true,
		vala_args: vala_args,
		c_args: c_args,
		install: true,
	)
	if host_machine.system() == 'linux'
		# Same classes as the desktop agent, without the registration window.
		# Left out of valadoc because the type names are already documented.
		executable(
			'argusrm-agent',
			files(
				'namespace.vala',
				'Application.vala',
				'Download.vala',
				'OSQuery/Initialize.vala',
				'OSQuery/Execute.vala',
				'OSQuery/LoggedInUsers.vala',
				'OSQuery/Package.vala',
				'OSQuery/DebPackages.vala',
				'OSQuery/RpmPackages.vala',
				'OSQuery/Programs.vala',
				'linux/Application.cli.vala',
				'linux/ServiceManager.vala',
				'linux/Command.vala',
				'linux/PackageMonitor.vala',
				'linux/UserMonitor.vala',
				'linux/UpdatesAvailable.vala',
				'linux/main.vala',
			),
			dependencies: [
				shared_cli_dep,
				dependency('gio-unix-2.0'),
			],
			vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
				'--pkg', 'gee-0.8', '--pkg', 'libsoup-3.0',
				'--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
				'--pkg', 'gio-unix-2.0', '--pkg', 'posix',
				'-D', 'LINUX',
			],
			c_args: c_args,
			install: true,
		)
	endif
	watch_test = executable(
		'argus-agent-watch',
		files('tests/watch.vala', 'tests/TlsClient.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			dependency('libsoup-3.0'),
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
		],
		install: false,
	)
	test('agent-watch', watch_test, timeout: 10)
	sync_lag_test = executable(
		'argus-agent-sync-lag',
		files('tests/sync-lag.vala', 'tests/TlsClient.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			dependency('libsoup-3.0'),
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
		],
		install: false,
	)
	test('agent-sync-lag', sync_lag_test, timeout: 15)
	if host_machine.system() == 'linux'
		command_test = executable(
			'argus-agent-command',
			files('tests/command.vala', 'linux/Command.vala'),
			dependencies: [
				dependency('glib-2.0'),
				dependency('gio-2.0'),
				dependency('gio-unix-2.0'),
				dependency('gee-0.8'),
				dependency('json-glib-1.0'),
				dependency('libsoup-3.0'),
				ocrpc_dep,
			],
			vala_args: ocrpc_vala_args + [
				'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0',
				'--pkg', 'libsoup-3.0', '--pkg', 'gio-unix-2.0', '--pkg', 'posix',
			],
			install: false,
		)
		test('agent-command', command_test, timeout: 8, is_parallel: false)
	endif
endif
