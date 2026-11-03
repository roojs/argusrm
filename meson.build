project(
	'argus',
	'vala',
	version: '0.1.0',
	meson_version: '>= 1.0.0',
	default_options: [
		'buildtype=debugoptimized',
		'prefix=/usr',
		'sysconfdir=/etc',
		'localstatedir=/var',
	],
)

subdir('shared')
subdir('agent')
subdir('server')
subdir('controller')

if host_machine.system() == 'linux'
	install_data(
		'packaging/systemd/argusrm-agent.service',
		'packaging/systemd/argusrm-server.service',
		install_dir: get_option('prefix') / 'lib' / 'systemd' / 'system',
	)
endif
