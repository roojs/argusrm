project(
	'argus',
	'vala',
	'c',
	version: '0.1.36',
	license: 'LGPL-3.0-or-later',
	meson_version: '>= 1.0.0',
	default_options: [
		'buildtype=debugoptimized',
		'prefix=/usr',
		'sysconfdir=/etc',
		'localstatedir=/var',
	],
)

fs = import('fs')
cc = meson.get_compiler('c')
ocsqlite_c_args = []
ocsqlite_vala_args = []
ocrpc_dep = declare_dependency()
ocrpc_vala_args = []

if host_machine.system() == 'android'
	gnome = import('gnome')
	# libocsqlite/meson.build compiles a typelib only when this is found.
	g_ir_compiler = disabler()
	valac_exe = find_program('valac')
	pixie_deps = [
		'glib-2.0',
		'gobject-2.0',
		'gio-2.0',
		'gee-0.8',
		'json-glib-1.0',
		'libsoup-3.0',
		'sqlite3',
		'gtk4',
		'libadwaita-1',
		'gioopenssl',
		'ocrpc',
		'ocsqlite',
	]
	foreach dep_name : pixie_deps
		dep = dependency(dep_name, allow_fallback: false, required: false)
		if not dep.found() or dep.type_name() != 'pkgconfig'
			error(
				'ILLEGAL CHANGE HAS BEEN DONE — DO NOT BUILD THIS. ' +
				'Android dependency "' + dep_name + '" is not provided by Pixie pkg-config. ' +
				'Report to the user: Pixie packages need updating at source, not here.'
			)
		endif
	endforeach
	gee_dep = dependency('gee-0.8', allow_fallback: false)
	gee_vapi_dir = gee_dep.get_variable(pkgconfig: 'prefix') / 'share' / 'vala' / 'vapi'
	add_project_arguments(['--vapidir', gee_vapi_dir], language: 'vala')
	add_project_arguments([
		'--pkg=json-glib-1.0',
		'--pkg=libsoup-3.0',
	], language: 'vala')
	ocrpc_dep = dependency('ocrpc', allow_fallback: false)
	ocsqlite_dep = dependency('ocsqlite', allow_fallback: false)
	ocrpc_vala_args = ['--pkg', 'ocrpc']
	ocsqlite_vala_args = ['--pkg', 'ocsqlite']
	ocsqlite_inc = ocsqlite_dep.get_variable(pkgconfig: 'includedir', default_value: '')
	ocsqlite_c_args = ocsqlite_inc == '' ? [] : ['-I' + ocsqlite_inc]
else
	if not cc.has_header('ocsqlite.h')
		ocsqlite_header_dir = ''
		# Linux leaves the header in OLLMchat/build. The Windows install
		# ships the import library in that slot and leaves ocsqlite.h in
		# OLLMchat/build-windows.
		foreach build_name : ['build', 'build-windows']
			candidate = meson.project_source_root() / '..' / 'OLLMchat' / build_name / 'libocsqlite'
			if fs.exists(candidate / 'ocsqlite.h')
				ocsqlite_header_dir = candidate
				break
			endif
		endforeach
		if ocsqlite_header_dir == ''
			error('ocsqlite.h is not installed')
		endif
		ocsqlite_c_args = ['-I' + ocsqlite_header_dir]
	endif
	ocsqlite_dep = cc.find_library('ocsqlite')
	ocsqlite_vala_args = ['--pkg', 'ocsqlite']
	ocrpc_dep = meson.get_compiler('c').find_library('ocrpc')
	ocrpc_vala_args = ['--pkg', 'ocrpc']
endif

sysconfdir = get_option('sysconfdir')
if not sysconfdir.startswith('/')
	sysconfdir = get_option('prefix') / sysconfdir
endif
localstatedir = get_option('localstatedir')
if not localstatedir.startswith('/')
	localstatedir = get_option('prefix') / localstatedir
endif
bindir = get_option('bindir')
if not bindir.startswith('/')
	bindir = get_option('prefix') / bindir
endif
server_executable = bindir / 'argusrm-server'
agent_executable = bindir / 'argusrm-agent-gtk'
agent_cli_executable = bindir / 'argusrm-agent'
paths_vala = configure_file(
	input: 'paths.vala.in',
	output: 'paths.vala',
	configuration: {
		'AGENT_DATA_DIR': localstatedir / 'lib' / 'argusrm-agent' / 'argus',
		'AGENT_SYSVINIT': sysconfdir / 'init.d' / 'argusrm-agent',
		'SERVER_SYSCONFDIR': sysconfdir / 'argusrm',
		'SERVER_DATA_DIR': localstatedir / 'lib' / 'argusrm',
		'CONTROLLER_EXECUTABLE': bindir / 'argusrm-controller',
		'SERVER_EXECUTABLE': server_executable,
		'LOG_DIR': localstatedir / 'log' / 'argusrm',
		'SOCKET_PORT': get_option('socket_port').to_string(),
		'DOWNLOAD_PORT': get_option('download_port').to_string(),
		'REGISTER_PORT': get_option('register_port').to_string(),
		'VERSION': meson.project_version(),
	},
)
agent_sysvinit = configure_file(
	input: 'packaging/sysvinit/argusrm-agent.in',
	output: 'argusrm-agent',
	configuration: {
		'AGENT_EXECUTABLE': agent_cli_executable,
		'AGENT_STATE_DIR': localstatedir / 'lib' / 'argusrm-agent',
		'LOG_DIR': localstatedir / 'log' / 'argusrm',
	},
)
server_sysvinit = configure_file(
	input: 'packaging/sysvinit/argusrm-server.in',
	output: 'argusrm-server',
	configuration: {
		'SERVER_EXECUTABLE': server_executable,
		'SERVER_DATA_DIR': localstatedir / 'lib' / 'argusrm',
		'SERVER_SYSCONFDIR': sysconfdir / 'argusrm',
		'LOG_DIR': localstatedir / 'log' / 'argusrm',
	},
)
subdir('shared')
subdir('agent')
subdir('controller')
if host_machine.system() == 'linux'
	subdir('server')
endif
subdir('tests')
if host_machine.system() == 'linux'
	freerdp = dependency('freerdp3', required: false)
	freerdp_server = dependency('freerdp-server3', required: false)
	winpr = dependency('winpr3', required: false)
	sdl_freerdp = find_program('sdl-freerdp3', required: false)
	if freerdp.found() and freerdp_server.found() and winpr.found() and sdl_freerdp.found()
		# Valac writes C next to the source relative to this file.
		# Listing agent/ and controller/ from server/meson.build makes
		# those paths climb out of the server directory and the
		# generated C is not where the C compiler looks.
		rdp_native = declare_dependency(
			compile_args: run_command(
				'pkg-config', '--cflags', 'freerdp3', 'freerdp-server3', 'winpr3',
				check: true
			).stdout().split(),
			link_args: run_command(
				'pkg-config', '--libs', 'freerdp3', 'freerdp-server3', 'winpr3',
				check: true
			).stdout().split(),
		)
		rdp_desk = executable(
			'argus-rdp-desk',
			files('agent/Rdp/Desk.vala', 'server/tests/rdp-desk.vala'),
			dependencies: [
				dependency('glib-2.0'),
				dependency('gobject-2.0'),
				rdp_native,
			],
			vala_args: [
				'--vapidir', meson.current_source_dir() / 'server' / 'vapi',
				'--pkg', 'freerdp',
			],
			install: false,
		)
		rdp_relay_test = executable(
			'argus-rdp-relay-test',
			server_sources,
			files(
				'agent/Rdp/Tunnel.vala',
				'controller/Rdp/Viewer.vala',
				'server/tests/rdp-relay-agent-application.vala',
				'server/tests/rdp-relay.vala',
			),
			dependencies: server_deps,
			c_args: ocsqlite_c_args,
			export_dynamic: true,
			vala_args: server_vala_args,
			install: false,
		)
		test(
			'rdp-relay',
			rdp_relay_test,
			args: [rdp_desk.full_path(), sdl_freerdp.full_path()],
			timeout: 60,
		)
	endif
	rdp_seat_test = executable(
		'argus-rdp-seat-test',
		files('shared/Rdp.vala', 'server/Rdp/Seat.vala', 'server/tests/rdp-seat.vala'),
		dependencies: [
			dependency('glib-2.0'),
			dependency('gobject-2.0'),
			dependency('gio-2.0'),
			dependency('gee-0.8'),
			dependency('json-glib-1.0'),
			dependency('libsoup-3.0'),
			ocrpc_dep,
		],
		vala_args: ocrpc_vala_args + [
			'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0', '--pkg', 'libsoup-3.0',
			'--pkg', 'posix',
		],
		install: false,
	)
	test('rdp-seat', rdp_seat_test, args: ['prove'], timeout: 30)
endif

if host_machine.system() == 'linux'
	install_data(
		'packaging/systemd/argusrm-agent.service',
		'packaging/systemd/argusrm-server.service',
		install_dir: get_option('prefix') / 'lib' / 'systemd' / 'system',
	)
	install_data(
		agent_sysvinit,
		server_sysvinit,
		install_dir: get_option('sysconfdir') / 'init.d',
		install_mode: 'rwxr-xr-x',
	)
	install_data(
		'packaging/logrotate/argusrm-agent',
		'packaging/logrotate/argusrm-server',
		install_dir: get_option('sysconfdir') / 'logrotate.d',
	)
	install_data(
		'packaging/xdg/argusrm-agent-gtk.desktop',
		install_dir: get_option('sysconfdir') / 'xdg' / 'autostart',
	)
	install_data(
		'packaging/xdg/org.roojs.ArgusController.desktop',
		install_dir: get_option('datadir') / 'applications',
	)
	install_data(
		'argusrm.svg',
		rename: 'org.roojs.ArgusController.svg',
		install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
	)
	install_data(
		'packaging/dbus/org.roojs.ArgusAgent.conf',
		install_dir: get_option('datadir') / 'dbus-1' / 'system.d',
	)
endif

if get_option('docs') and host_machine.system() != 'android'
	subdir('docs')
endif
