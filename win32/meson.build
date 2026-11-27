# Windows FFI and small C helpers (win32.vapi, pe-authenticode, register-pipe).
# Linked into the Windows agent; not agent product code.

win32_src = meson.current_source_dir()
win32_c_sources = files(
	'pe-authenticode.c',
	'register-pipe.c',
	'adapter-row.c',
	'desktop-share.c',
)
win32_c_args = ['-I' + win32_src]
win32_vala_args = ['--vapidir', win32_src, '--pkg', 'win32']