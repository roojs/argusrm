/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * Local registration JSON and OLLMrpc bin round-trip for
 * {@link Argus.Shared.SQT.Server}.
 */
class RegistrationWireTest
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

	static bool bootstrap_ready(Argus.Shared.SQT.Server data)
	{
		if (data.error != "") {
			return false;
		}
		if (data.name == "" || data.port < 1) {
			return false;
		}
		return data.has_certificate;
	}

	static int main()
	{
		OLLMrpc.rpc_register();
		Argus.Shared.SQT.rpc_register();
		var issued = new Argus.Shared.SQT.Server() {
			name = "regtest-host",
			port = 817,
			addresses = "192.0.2.1\n192.0.2.2",
			pem_private_key = "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n",
			pem_client_certificate = "-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----\n",
			pem_ca_certificate = "-----BEGIN CERTIFICATE-----\nca\n-----END CERTIFICATE-----\n"
		};
		var json = Json.gobject_to_data(issued, null);
		note(json.contains("192.0.2.1"), "JSON keeps newline addresses");
		note(!json.contains("private_key"), "JSON has no legacy private_key field");
		note(!json.contains("has-certificate"), "JSON omits computed has-certificate");
		note(!json.contains("addresses-subtitle"), "JSON omits computed addresses-subtitle");
		Argus.Shared.SQT.Server? parsed = null;
		try {
			parsed = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), json)
				as Argus.Shared.SQT.Server;
		} catch (GLib.Error e) {
			note(false, "JSON deserializes");
			return 1;
		}
		note(parsed != null, "JSON deserializes");
		note(parsed != null && parsed.pem_private_key != "", "JSON round-trip pem_private_key");
		note(parsed != null && parsed.name == issued.name, "JSON round-trip name");
		note(parsed != null && parsed.port == issued.port, "JSON round-trip port");
		note(parsed != null && parsed.addresses == issued.addresses, "JSON round-trip addresses");
		note(parsed != null && parsed.has_certificate, "JSON round-trip has_certificate");
		note(bootstrap_ready(parsed), "Bootstrap readiness on success row");
		var failure = new Argus.Shared.SQT.Server() {
			error = "This machine is already registered."
		};
		var fail_json = Json.gobject_to_data(failure, null);
		var fail_parsed = Json.gobject_from_data(typeof(Argus.Shared.SQT.Server), fail_json)
			as Argus.Shared.SQT.Server;
		note(fail_parsed != null && fail_parsed.error == failure.error, "failure error round-trip");
		note(!bootstrap_ready(fail_parsed), "Bootstrap rejects error row");
		var packed = OLLMrpc.val("o", issued);
		var row = packed as Argus.Shared.SQT.Server;
		note(row != null && row.pem_ca_certificate == issued.pem_ca_certificate,
			"OLLMrpc val round-trip PEM");
		return failures == 0 ? 0 : 1;
	}
}