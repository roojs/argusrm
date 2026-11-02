deps = [shared_dep, dependency('gtk4'), dependency('libadwaita-1')]
sources = files('namespace.vala', 'Application.vala')
vala_args = ['--pkg', 'gtk4', '--pkg', 'libadwaita-1', '--pkg', 'ocrpc']
c_args = []

if host_machine.system() == 'linux'
	sources += files('linux/BusRegistration.vala')
	vala_args += ['-D', 'LINUX']
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
	sources += files('Win32/Service.vala', 'Win32/tray/Tray.vala')
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
