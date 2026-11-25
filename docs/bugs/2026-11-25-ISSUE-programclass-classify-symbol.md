# ProgramClass.classify never answers

**Status:** fixed in the source. The running server still needs a rebuild and a restart.

## Symptom

Choosing System on the Software page shows `call timed out`. The flag does not change.

## Cause

`Request.add_class` looks up `argus_shared_os_query_program_class_classify`. Vala names a class that ends in `Class` without that underscore, so the function is `argus_shared_os_query_programclass_classify`. The lookup misses, and `Ffi` returns without a reply.

`PackageMachine` is `argus_shared_os_query_package_machine_machines`, which matches the lookup. Only the `Class` ending differs.

## Evidence

`/tmp/programclass-cname.vala` compiled with `valac -C`. Before the attribute, the function was `argus_shared_os_query_programclass_classify`. The same regex as `Request.add_class` on `ArgusSharedOSQueryProgramClass` asks for `argus_shared_os_query_program_class_classify`. After `[CCode (cname = "argus_shared_os_query_program_class_classify")]`, the throwaway function has that name.

## Fix

The same attribute is on `ProgramClass.classify`.
