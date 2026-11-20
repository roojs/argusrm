# NOTE: If you add/remove/change source files in this directory, you MUST also
# update docs/meson.build to include the same files in the valadoc input list.

# The server links shared_server_dep. That library has the database rows.
# The command-line agent links shared_cli_dep. That library adds Linux
# broadcast browse and does not link GTK.
# GTK, Adwaita, libsecret, and the controller registration result
# belong to the agent and controller library in shared_dep.
shared_deps = [
	dependency('glib-2.0'),
	dependency('gobject-2.0'),
	dependency('gio-2.0'),
	dependency('gee-0.8'),
	dependency('json-glib-1.0'),
	dependency('libsoup-3.0'),
	dependency('sqlite3'),
	ocrpc_dep,
	ocsqlite_dep,
]
shared_osquery_sources = files(
	'SQ/Interface.vala',
	'OSQuery/namespace.vala',
	'OSQuery/AgentInfo.vala',
	'OSQuery/Row.vala',
	'OSQuery/Package.vala',
	'OSQuery/SystemInfo.vala',
	'OSQuery/CpuInfo.vala',
	'OSQuery/Uptime.vala',
	'OSQuery/Mounts.vala',
	'OSQuery/LoggedInUsers.vala',
	'OSQuery/Users.vala',
	'OSQuery/Groups.vala',
	'OSQuery/UserGroups.vala',
	'OSQuery/InterfaceAddresses.vala',
	'OSQuery/OsVersion.vala',
	'OSQuery/DebPackages.vala',
	'OSQuery/RpmPackages.vala',
	'OSQuery/Programs.vala',
	'OSQuery/PackageUpdates.vala',
	'OSQuery/AptSources.vala',
	'OSQuery/AptExplicitInstall.vala',
)
shared_sqt_sources = files(
	'SQT/namespace.vala',
	'SQT/Task.vala',
	'SQT/TaskTarget.vala',
	'SQT/Script.vala',
	'SQT/ScriptPerm.vala',
	'SQT/ScriptRepository.vala',
	'SQT/Distributable.vala',
	'SQT/DistributableVersion.vala',
	'SQT/AptUrl.vala',
	'SQT/AptPkg.vala',
	'SQT/AptPkgDepends.vala',
	'SQT/Server.vala',
)
shared_sqv_sources = files(
	'SQV/namespace.vala',
	'SQV/DistributeMachine.vala',
	'SQV/PackageMachine.vala',
	'SQV/AptDepends.vala',
)
shared_sources = files(
	'namespace.vala',
	'Rdp.vala',
	'Agent.vala',
	'AgentPending.vala',
	'OsReleases.vala',
	'Register.vala',
)
shared_sources += paths_vala
shared_sources += shared_osquery_sources
shared_sources += shared_sqt_sources
shared_sources += shared_sqv_sources
shared_sources += files('linux/Net/Route.vala')
shared_vala_args = ocrpc_vala_args + ocsqlite_vala_args + [
	'--pkg', 'sqlite3',
]
shared_c_args = ocsqlite_c_args

shared_ui_deps = [
	dependency('gtk4'),
	dependency('libadwaita-1'),
]
shared_ui_sources = files(
	'RegisterWindow.vala',
	'Notice.vala',
)
shared_ui_vala_args = [
	'--pkg', 'gtk4', '--pkg', 'libadwaita-1',
]
shared_ui_c_args = []

if host_machine.system() == 'windows'
	# MSYS2 valac does not predefine this, so Register stays on the Linux path.
	shared_vala_args += ['-D', 'G_OS_WIN32']
	shared_ui_sources += files('windows/Browse.vala')
	shared_ui_deps += meson.get_compiler('c').find_library('dnsapi')
	shared_ui_vala_args += ['--vapidir', meson.current_source_dir() / 'windows', '--pkg', 'windns']
	shared_ui_c_args += [
		'-DUNICODE', '-D_UNICODE',
		'-I' + meson.current_source_dir() / 'windows',
	]
elif host_machine.system() == 'android'
	shared_ui_sources += files('android/Browse.vala', 'android/pair-browse.c')
	shared_ui_vala_args += [
		'--vapidir', meson.current_source_dir() / 'android', '--pkg', 'pair-browse',
		'-D', 'ANDROID',
	]
	# Generated Browse.c includes <pair-browse.h>. The header sits next to
	# the C file, and the generated source is compiled from the build tree.
	shared_ui_c_args += ['-I' + meson.current_source_dir() / 'android']
else
	shared_ui_sources += files('Browse.vala')
	shared_ui_deps += dependency('avahi-gobject')
	shared_ui_deps += dependency('avahi-client')
endif

if host_machine.system() == 'linux'
	libnl = dependency('libnl-3.0')
	nl_route = meson.get_compiler('c').find_library('nl-route-3', required: false)
	if not nl_route.found()
		nl_route = declare_dependency(link_args: ['-l:libnl-route-3.so.200'])
	endif
	shared_deps += [libnl, nl_route]
	shared_vala_args += [
		'-D', 'LINUX', '--pkg', 'posix',
		'--vapidir', meson.project_source_root() / 'server/vapi',
		'--pkg', 'libnl-3.0',
	]
	shared_ui_deps += dependency('libsecret-1')
	shared_ui_vala_args += ['-D', 'LINUX', '--pkg', 'libsecret-1']
endif

shared_server_lib = static_library(
	'argus-shared-server',
	shared_sources,
	dependencies: shared_deps,
	vala_args: shared_vala_args,
	c_args: shared_c_args,
)

shared_server_dep = declare_dependency(
	link_with: shared_server_lib,
	dependencies: shared_deps,
	include_directories: include_directories('.'),
)

# Linux command-line agent. Browse uses Avahi. The registration window stays
# in shared_lib, so this library does not link GTK, Adwaita, or libsecret.
if host_machine.system() == 'linux'
	shared_cli_deps = shared_deps + [
		dependency('avahi-gobject'),
		dependency('avahi-client'),
	]
	shared_cli_lib = static_library(
		'argus-shared-cli',
		shared_sources,
		files('Browse.vala'),
		dependencies: shared_cli_deps,
		vala_args: shared_vala_args,
		c_args: shared_c_args,
	)
	shared_cli_dep = declare_dependency(
		link_with: shared_cli_lib,
		dependencies: shared_cli_deps,
		include_directories: include_directories('.'),
	)
endif

shared_lib = static_library(
	'argus-shared',
	shared_sources + shared_ui_sources,
	dependencies: shared_deps + shared_ui_deps,
	vala_args: shared_vala_args + shared_ui_vala_args,
	c_args: shared_c_args + shared_ui_c_args,
)

shared_dep = declare_dependency(
	link_with: shared_lib,
	dependencies: shared_deps + shared_ui_deps,
	include_directories: include_directories('.'),
)
