# Test programs. The top-level meson.build includes this directory.
# Nothing here is installed.

if host_machine.system() != 'android'
	watch_test = executable(
		'argus-agent-watch',
		files('watch.vala', 'TlsClient.vala'),
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
		files('sync-lag.vala', 'TlsClient.vala'),
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
endif

if host_machine.system() == 'linux'
	# Valac writes C for a source outside this directory somewhere
	# other than Meson looks. Copy the live file into this build
	# so both agree.
	command_live = custom_target(
		'linux-command-vala',
		input: files('../agent/linux/Command.vala'),
		output: 'linux-Command.vala',
		command: ['cp', '@INPUT@', '@OUTPUT@'],
	)
	history_live = custom_target(
		'linux-history-vala',
		input: files('../agent/linux/Apt/History.vala'),
		output: 'linux-History.vala',
		command: ['cp', '@INPUT@', '@OUTPUT@'],
	)
	command_test = executable(
		'argus-agent-command',
		files('command.vala'),
		command_live,
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
	apt_history_test = executable(
		'argus-apt-history-test',
		files('apt-history.vala'),
		history_live,
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			shared_cli_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'gio-2.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	test('apt-history', apt_history_test, timeout: 30)
endif
