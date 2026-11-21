/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Agent
{
	/**
	 * Stand-in for {@link Argus.Agent.Application} in ''argus-rdp-relay-test'' only.
	 *
	 * The production agent is not linked into that binary; {@link Argus.Agent.Rdp.Tunnel}
	 * still references this type for the Windows ''open_windows'' path.
	 */
	public class Application : GLib.Application
	{
		internal OLLMrpc.Transport.TlsClient? connection { get; set; }

		public Application()
		{
			Object(application_id: "org.roojs.argus.rdp-relay-test");
		}
	}
}