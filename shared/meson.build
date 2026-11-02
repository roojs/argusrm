shared_deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('gtk4'),
	dependency('libadwaita-1'),
	meson.get_compiler('c').find_library('ocrpc'),
]
shared_sources = files(
	'namespace.vala',
	'Register.vala',
	'RegisterWindow.vala',
	'OSQuery/Row.vala',
	'OSQuery/SystemInfo.vala',
	'OSQuery/CpuInfo.vala',
	'OSQuery/LoggedInUsers.vala',
	'OSQuery/InterfaceAddresses.vala',
)
shared_vala_args = ['--pkg', 'ocrpc', '--pkg', 'gtk4', '--pkg', 'libadwaita-1']
shared_c_args = []

if host_machine.system() == 'windows'
	shared_sources += files('windows/Browse.vala')
	shared_deps += meson.get_compiler('c').find_library('dnsapi')
	shared_vala_args += ['--vapidir', meson.current_source_dir() / 'windows', '--pkg', 'windns']
	shared_c_args += ['-DUNICODE', '-D_UNICODE']
elif host_machine.system() == 'android'
	shared_sources += files('android/Browse.vala', 'android/pair-browse.c')
	shared_vala_args += [
		'--vapidir', meson.current_source_dir() / 'android', '--pkg', 'pair-browse',
		'-D', 'ANDROID',
	]
else
	shared_sources += files('Browse.vala')
	shared_deps += dependency('avahi-gobject')
	shared_deps += dependency('avahi-client')
endif

shared_lib = static_library(
	'argus-shared',
	shared_sources,
	dependencies: shared_deps,
	vala_args: shared_vala_args,
	c_args: shared_c_args,
)

shared_dep = declare_dependency(
	link_with: shared_lib,
	dependencies: shared_deps,
	include_directories: include_directories('.'),
)
