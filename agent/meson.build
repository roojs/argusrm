deps = [shared_dep, dependency('gtk4'), dependency('libadwaita-1')]
sources = files(
	'namespace.vala',
	'Application.vala',
	'Download.vala',
)
vala_args = [
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1', '--pkg', 'libsoup-3.0', '--pkg', 'ocrpc',
	'--pkg', 'gee-0.8', '--pkg', 'json-glib-1.0',
]
c_args = []

if host_machine.system() == 'linux'
	deps += dependency('gio-unix-2.0')
	sources += files(
		'OSQuery/Initialize.vala',
		'OSQuery/Query.vala',
		'linux/BusRegistration.vala',
		'linux/Command.vala',
		'Listen.vala',
	)
	vala_args += ['-D', 'LINUX', '--pkg', 'gio-unix-2.0']
	install_data(
		'org.roojs.ArgusAgent.conf',
		install_dir: get_option('datadir') / 'dbus-1' / 'system.d',
	)
else
	sources += files('Win32/BusRegistration.vala')
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
		'Win32/tray/Tray.vala',
		'Win32/Command.vala',
		'Listen.vala',
	)
	vala_args += [
		'--vapidir', meson.current_source_dir() / 'Win32', '--pkg', 'win32',
		'-D', 'WINDOWS',
	]
	c_args += ['-I' + meson.current_source_dir() / 'Win32']
endif

if host_machine.system() == 'android'
	if not meson.version().version_compare('>=1.8.0')
		error('Android agent requires Meson >= 1.8.0 for android_exe_type')
	endif
	sources += files('android/OSQuery/Initialize.vala', 'android/Command.vala', 'Listen.vala')
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
endif
