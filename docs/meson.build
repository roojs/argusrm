# Generate Valadoc documentation (single unified documentation)
# valadoc is required - meson will fail during configuration if it's not found
#
# IMPORTANT: When adding/removing/changing source files in any directory,
# you MUST update the input files list below to match.
# Check the corresponding meson.build file in each directory for the
# current list of source files. Those meson.build files note this explicitly.
#
# Markup rules for docblocks:
#   - Use {{{ }}} for literals; NOT {@code …} (valadoc error)
#   - File order: types/interfaces before users
# Verify locally: ninja -C build docs/valadoc
#
valadoc = find_program('valadoc', required: true)
valadoc_runner = find_program(
  meson.current_source_dir() / 'run-valadoc.sh'
)

# Combined documentation for shared, agent, server, and controller.
# Output to build directory instead of source directory to keep generated files out of repository
# Valadoc creates a subdirectory with the package name (argus) inside the specified directory
# So we point it to build/valadoc and it creates build/valadoc/argus/
# IMPORTANT: We build docs in a slightly odd location (build/valadoc instead of standard build location),
# so we need to manually clean the directory before building to avoid "file already exists" errors.
# This clean step should NOT be removed - meson's automatic cleaning doesn't handle this case.
valadoc_dir = meson.project_build_root() / 'valadoc'
valadoc_clean = custom_target('valadoc-clean',
  output: 'valadoc-clean',
  command: [
    find_program('sh'),
    '-c',
    '''if [ -d "@0@" ]; then
      # Remove the directory completely (valadoc needs to recreate it)
      rm -rf "@0@"
    fi'''.format(valadoc_dir)
  ],
  build_by_default: false
)

# IMPORTANT: We list ALL source files explicitly instead of using --pkg for internal code.
# This is because valadoc processes source files directly, and using --pkg with VAPI files
# causes duplicate definition errors (the VAPI contains the same definitions as the source files).
# When adding new files, add their source files to this list rather than using --pkg.
# NOTE: File order matters! Files that define types must come before files that use those types.
# Linux sources only. Windows and Android trees are build-only.
valadoc_sources = files(
  # shared sources (must come before agent, server, and controller)
  '../shared/namespace.vala',
  '../shared/Agent.vala',
  '../shared/Registration/Data.vala',
  '../shared/Register.vala',
  '../shared/RegisterWindow.vala',
  '../shared/Notice.vala',
)
valadoc_sources += paths_vala
valadoc_sources += files(
  '../shared/SQ/Interface.vala',
  '../shared/OSQuery/namespace.vala',
  '../shared/OSQuery/AgentInfo.vala',
  '../shared/OSQuery/Row.vala',
  '../shared/OSQuery/SystemInfo.vala',
  '../shared/OSQuery/CpuInfo.vala',
  '../shared/OSQuery/LoggedInUsers.vala',
  '../shared/OSQuery/InterfaceAddresses.vala',
  '../shared/SQT/namespace.vala',
  '../shared/SQT/Task.vala',
  '../shared/SQT/TaskTarget.vala',
  '../shared/SQT/Script.vala',
  '../shared/SQT/ScriptAgent.vala',
  '../shared/SQT/ScriptRepository.vala',
  '../shared/Browse.vala',
  # agent sources
  '../agent/namespace.vala',
  '../agent/Application.vala',
  '../agent/Download.vala',
  '../agent/OSQuery/Initialize.vala',
  '../agent/OSQuery/Query.vala',
  '../agent/linux/Application.vala',
  '../agent/linux/ServiceManager.vala',
  '../agent/linux/Command.vala',
  # server sources
  '../server/namespace.vala',
  '../server/Net/namespace.vala',
  '../server/Net/SslListen.vala',
  '../server/Net/SslConnection.vala',
  '../server/Net/Download.vala',
  '../server/Net/NFTables.vala',
  '../server/Net/Address.vala',
  '../server/Net/Interfaces.vala',
  '../server/Application.vala',
  '../server/Initialize.vala',
  '../server/GitHub.vala',
  '../server/Agent.vala',
  '../server/Registration.vala',
  '../server/OSQuery.vala',
  '../server/Command.vala',
  '../server/SQT/Script.vala',
  '../server/SQT/ScriptRepository.vala',
  '../server/SQT/Scheduler.vala',
  '../server/SQT/Task.vala',
  '../server/Git/Callbacks.vala',
  '../server/Daemon.vala',
  '../server/main.vala',
  # controller sources
  '../controller/namespace.vala',
  '../controller/Application.vala',
  '../controller/Connection.vala',
  '../controller/Bootstrap.vala',
  '../controller/PairingDialog.vala',
  '../controller/Window.vala',
  '../controller/Pin.vala',
  '../controller/Agents.vala',
  '../controller/Command.vala',
)
valadoc_docs = custom_target('valadoc',
  input: valadoc_sources,
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc_runner,
    valadoc_dir,
    '--package-name=argus',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../server/vapi',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg=gee-0.8',
    '--pkg=gio-2.0',
    '--pkg=gio-unix-2.0',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=json-glib-1.0',
    '--pkg=libsoup-3.0',
    '--pkg=gtk4',
    '--pkg=libadwaita-1',
    '--pkg=sqlite3',
    '--pkg=ocsqlite',
    '--pkg=ocrpc',
    '--pkg=posix',
    '--pkg=libsecret-1',
    '--pkg=avahi-gobject',
    '--pkg=avahi-client',
    '--pkg=gnutls',
    '--pkg=libgit2-glib-1.0',
    '--pkg=libnftables',
    '--pkg=libnl-3.0',
    '-D', 'LINUX',
    # One valadoc package is one program. The agent, server, and controller
    # each keep their own main; this define leaves those entry points out.
    '-D', 'VALADOC',
    # Don't use --pkg for internal code.
    # - valadoc processes source files directly, so it doesn't need VAPI files.
    # Using --pkg would cause duplicate definition errors since the VAPI contains the same definitions.
    '--doclet=html',
    '--wiki=@0@'.format(meson.current_source_dir() / 'valadoc-wiki'),
    '--directory=' + valadoc_dir,
    '@INPUT@'
  ],
  # Docs are optional; default `ninja` should only rebuild the app.
  build_by_default: false,
  install: false
)
