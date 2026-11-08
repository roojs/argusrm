project(
	'argus',
	'vala',
	'c',
	version: '0.1.1',
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
	gee_vapi_dir = meson.project_source_root() / 'subprojects' / 'libgee-0.20.8' / 'gee'
	if not fs.exists(meson.project_source_root() / 'vendor' / 'libocrpc' / 'meson.build')
		error('Android builds require vendor/libocrpc staged from the pinned OLLMchat revision')
	endif
	if not fs.exists(meson.project_source_root() / 'vendor' / 'libocsqlite' / 'meson.build')
		error('Android builds require vendor/libocsqlite staged from the pinned OLLMchat revision')
	endif
	# Android subprojects build these libraries without Vala bindings, so
	# Meson does not pass --pkg for them. The host valac still has the
	# bindings.
	add_project_arguments([
		'--pkg=json-glib-1.0',
		'--pkg=libsoup-3.0',
	], language: 'vala')
	subdir('vendor/libocsqlite')
	subdir('vendor/libocrpc')
	ocrpc_dep = ocrpc_vapi_dep
	ocsqlite_dep = ocsqlite_vapi_dep
	ocsqlite_c_args = ['-I' + meson.project_build_root() / 'vendor' / 'libocsqlite']
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
agent_executable = bindir / 'argus-agent'
paths_vala = configure_file(
	input: 'paths.vala.in',
	output: 'paths.vala',
	configuration: {
		'AGENT_DATA_DIR': localstatedir / 'lib' / 'argusrm-agent' / 'argus',
		'AGENT_SYSVINIT': sysconfdir / 'init.d' / 'argusrm-agent',
		'SERVER_SYSCONFDIR': sysconfdir / 'argusrm',
		'SERVER_DATA_DIR': localstatedir / 'lib' / 'argusrm',
		'LOG_DIR': localstatedir / 'log' / 'argusrm',
		'SOCKET_PORT': get_option('socket_port').to_string(),
		'DOWNLOAD_PORT': get_option('download_port').to_string(),
	},
)
agent_sysvinit = configure_file(
	input: 'packaging/sysvinit/argusrm-agent.in',
	output: 'argusrm-agent',
	configuration: {
		'AGENT_EXECUTABLE': agent_executable,
		'AGENT_STATE_DIR': localstatedir / 'lib' / 'argusrm-agent',
		'LOG_DIR': localstatedir / 'log' / 'argusrm',
	},
)
server_executable = bindir / 'argus'
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
endif

if get_option('docs') and host_machine.system() != 'android'
	subdir('docs')
endif
