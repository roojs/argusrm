deps = [shared_dep]
sources = files('namespace.vala', 'Application.vala')
vala_args = []

if host_machine.system() == 'windows'
	deps += meson.get_compiler('c').find_library('advapi32')
	sources += files('Win32/Service.vala')
	vala_args += ['--vapidir', meson.current_source_dir() / 'Win32', '--pkg', 'win32', '-D', 'WINDOWS']
endif

executable(
	'argus-agent',
	sources,
	dependencies: deps,
	vala_args: vala_args,
	install: true,
)
