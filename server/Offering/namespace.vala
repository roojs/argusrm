/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * Registration desk: TLS listener, registration-port firewall, and
 * mDNS PairPublish for {@link Argus.Server.Offering.Network}.
 *
 * {@link Argus.Server.Offering.Rpc} is the only entry for registration
 * RPC. New code uses {@link Network} and Rpc — not legacy
 * ''Application.register_listen'' or ''Agent.offer''.
 */
namespace Argus.Server.Offering
{
	/**
	 * Register registration RPC methods.
	 */
	public static void rpc_register()
	{
		Rpc.rpc_register();
	}

	/**
	 * Register the registration handler with ''OLLMrpc''.
	 *
	 * @param app the running server
	 */
	public static void register(Application app)
	{
		OLLMrpc.Request.register("Offering",
			new Rpc.for_rpc(app, app.offering));
	}
}