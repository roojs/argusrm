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
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
]
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
		'OSQuery/Query.vala',
		'linux/Application.vala',
		'linux/ServiceManager.vala',
		'linux/Command.vala',
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
	sources += files(
		'OSQuery/Initialize.vala',
		'OSQuery/Query.vala',
		'Win32/Service.vala',
		'Win32/register-pipe.c',
		'Win32/tray/Tray.vala',
		'Win32/Command.vala',
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
endif

if host_machine.system() == 'android'
	if not meson.version().version_compare('>=1.8.0')
		error('Android agent requires Meson >= 1.8.0 for android_exe_type')
	endif
	sources += files(
		'android/OSQuery/Initialize.vala',
		'android/Command.vala',
		'android/main.vala',
	)
	vala_args += ['-D', 'ANDROID']
	executable(
		'argus-agent',
		sources,
		dependencies: deps,
		vala_args: vala_args,
		c_args: c_args,
		android_exe_type: 'application',
		install: true,
	)
else
	executable(
		'argus-agent',
		sources,
		dependencies: deps,
		vala_args: vala_args,
		c_args: c_args,
		install: true,
	)
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
