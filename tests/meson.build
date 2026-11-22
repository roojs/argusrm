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
	registration_wire_test = executable(
		'argus-registration-wire',
		files('registration-wire.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			shared_cli_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	test('registration-wire', registration_wire_test, timeout: 30)
	store_server_src = files('StoreServer.vala')
	registration_enroll_test = executable(
		'argus-registration-enroll',
		store_server_src,
		files('registration-enroll.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			shared_cli_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	test('registration-enroll', registration_enroll_test, timeout: 30)
	registration_bootstrap_test = executable(
		'argus-registration-bootstrap',
		store_server_src,
		files('registration-bootstrap.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			shared_cli_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	test('registration-bootstrap', registration_bootstrap_test, timeout: 30)
	list_probe_server = custom_target(
		'list-probe-server-vala',
		input: files('../controller/SQT/Server.vala'),
		output: 'list-probe-Server.vala',
		command: ['cp', '@INPUT@', '@OUTPUT@'],
	)
	# Manual throwaway; not registered with test() — needs live server + credentials.
	executable(
		'argus-list-probe',
		files('list-probe.vala'),
		list_probe_server,
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			dependency('libsecret-1'),
			shared_cli_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
			'-D', 'LINUX', '--pkg', 'libsecret-1',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	# Manual throwaway; needs a copy of /var/lib/argusrm/argus.sqlite (see agent-list-offline.vala).
	executable(
		'argus-db-startup-probe',
		files('db-startup-probe.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			shared_server_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
	executable(
		'argus-agent-list-offline',
		files('agent-list-offline.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			shared_server_dep,
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + ocsqlite_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'sqlite3',
		],
		c_args: ocsqlite_c_args,
		install: false,
	)
endif
