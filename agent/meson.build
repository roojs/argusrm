deps = [shared_dep, dependency('gtk4'), dependency('libadwaita-1')]
sources = files('namespace.vala', 'Application.vala')
vala_args = ['--pkg', 'gtk4', '--pkg', 'libadwaita-1']
c_args = []

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

executable(
	'argus-agent',
	sources,
	dependencies: deps,
	vala_args: vala_args,
	c_args: c_args,
	install: true,
)
