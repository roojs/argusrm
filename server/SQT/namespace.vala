/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Server.SQT
{
	/**
	 * Register stored row types and their calls.
	 *
	 * Handlers are {@link register}.
	 */
	public static void rpc_register()
	{
		ScriptRepository.rpc_register();
		Distributable.rpc_register();
		Script.rpc_register();
		Task.rpc_register();
	}

	/**
	 * Register all SQT RPC handlers with ''OLLMrpc''.
	 *
	 * @param app the running server
	 */
	public static void register(Application app)
	{
		OLLMrpc.Request.register("ScriptRepository", new ScriptRepository.for_rpc(app));
		OLLMrpc.Request.register("Script", new Script.for_rpc(app));
		OLLMrpc.Request.register("Task", new Task.for_rpc(app));
		OLLMrpc.Request.register("Distributable", new Distributable.for_rpc(app));
	}
}
