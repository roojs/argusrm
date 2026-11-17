/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Server.SQV
{
	/**
	 * Register view row types and their calls.
	 *
	 * Handlers are {@link register}.
	 */
	public static void rpc_register()
	{
		DistributeMachine.rpc_register();
		PackageMachine.rpc_register();
		AptDepends.rpc_register();
	}

	/**
	 * Register view RPC handlers with ''OLLMrpc''.
	 *
	 * @param app the running server
	 */
	public static void register(Application app)
	{
		OLLMrpc.Request.register("DistributeMachine", new DistributeMachine.for_rpc(app));
		OLLMrpc.Request.register("PackageMachine", new PackageMachine.for_rpc(app));
		OLLMrpc.Request.register("AptDepends", new AptDepends.for_rpc(app));
	}
}
