/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * ''argusrm-server --give-me-a-certificate'' without root: JSON on stdout, no crash.
 */
class RegistrationControllerCliTest
{
	static int failures = 0;

	static void note(bool ok, string message)
	{
		if (ok) {
			GLib.print("ok %s\n", message);
			return;
		}
		failures++;
		GLib.printerr("fail %s\n", message);
	}

	static int main(string[] args)
	{
		var executable = args.length > 1 ? args[1] : "";
		if (executable == "" ||
			!GLib.FileUtils.test(executable, GLib.FileTest.IS_EXECUTABLE)) {
			GLib.printerr("fail missing argusrm-server path\n");
			return 1;
		}
		string[] argv = {};
		argv += "env";
		argv += "-u";
		argv += "DISPLAY";
		argv += "-u";
		argv += "WAYLAND_DISPLAY";
		argv += executable;
		argv += "--give-me-a-certificate";
		argv += "controller";
		GLib.Subprocess proc;
		try {
			proc = new GLib.Subprocess.newv(argv,
				GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
		} catch (GLib.Error e) {
			GLib.printerr("fail spawn server client: %s\n", e.message);
			return 1;
		}
		string? stdout_text = null;
		string? stderr_text = null;
		try {
			proc.communicate_utf8(null, null, out stdout_text, out stderr_text);
		} catch (GLib.Error e) {
			GLib.printerr("fail communicate: %s\n", e.message);
			return 1;
		}
		var output = stdout_text != null ? stdout_text.strip() : "";
		note(output != "", "pkexec helper printed JSON");
		note(proc.get_if_exited(), "clean process exit (not signaled)");
		note(proc.get_successful() == false, "exits non-zero without root");
		note(output.index_of("root is required") >= 0, "JSON carries root error");
		note(output.index_of("pem-client-certificate") >= 0, "JSON is SQT.Server shape");
		note(!output.contains("BEGIN CERTIFICATE"), "no PEM on failure path");
		return failures == 0 ? 0 : 1;
	}
}