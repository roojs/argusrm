project(
	'argus',
	'vala',
	'c',
	version: '0.1.0',
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
if not cc.has_header('ocsqlite.h')
	ocsqlite_header_dir = meson.project_source_root() / '..' / 'OLLMchat' / 'build' / 'libocsqlite'
	if not fs.exists(ocsqlite_header_dir / 'ocsqlite.h')
		error('ocsqlite.h is not installed')
	endif
	ocsqlite_c_args = ['-I' + ocsqlite_header_dir]
endif
ocsqlite_dep = cc.find_library('ocsqlite')

ocrpc_dep = declare_dependency()
ocrpc_vala_args = []

if host_machine.system() == 'android'
	gnome = import('gnome')
	fs = import('fs')
	valac_exe = find_program('valac')
	gee_vapi_dir = meson.project_source_root() / 'subprojects' / 'libgee-0.20.8' / 'gee'
	if not fs.exists(meson.project_source_root() / 'vendor' / 'libocrpc' / 'meson.build')
		error('Android builds require vendor/libocrpc staged from the pinned OLLMchat revision')
	endif
	subdir('vendor/libocrpc')
	ocrpc_dep = ocrpc_vapi_dep
else
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
subdir('shared')
subdir('agent')
if host_machine.system() != 'android'
	subdir('server')
	subdir('controller')
endif

if host_machine.system() == 'linux'
	install_data(
		'packaging/systemd/argusrm-agent.service',
		'packaging/systemd/argusrm-server.service',
		install_dir: get_option('prefix') / 'lib' / 'systemd' / 'system',
	)
	install_data(
		agent_sysvinit,
		install_dir: get_option('sysconfdir') / 'init.d',
		install_mode: 'rwxr-xr-x',
	)
	install_data(
		'packaging/logrotate/argusrm-agent',
		'packaging/logrotate/argusrm-server',
		install_dir: get_option('sysconfdir') / 'logrotate.d',
	)
endif
