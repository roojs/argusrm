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
		'packaging/logrotate/argusrm-agent',
		'packaging/logrotate/argusrm-server',
		install_dir: get_option('sysconfdir') / 'logrotate.d',
	)
endif
