/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * Create all osquery tables.
	 *
	 * @param db Argus database
	 */
	public static void init_db(SQ.Database db)
	{
		SystemInfo.init_db(db);
		CpuInfo.init_db(db);
		Uptime.init_db(db);
		Mounts.init_db(db);
		LoggedInUsers.init_db(db);
		Users.init_db(db);
		Groups.init_db(db);
		UserGroups.init_db(db);
		InterfaceAddresses.init_db(db);
		OsVersion.init_db(db);
		DebPackages.init_db(db);
		AptExplicitInstall.init_db(db);
		RpmPackages.init_db(db);
		Programs.init_db(db);
		PackageUpdates.init_db(db);
	}

	/**
	 * Register osquery row types with the ''OLLMrpc'' bin codec.
	 *
	 * Agent, server, and controller call this before ''OSQuery.sync''.
	 */
	public static void rpc_register()
	{
		SystemInfo.rpc_register();
		CpuInfo.rpc_register();
		Uptime.rpc_register();
		Mounts.rpc_register();
		LoggedInUsers.rpc_register();
		Users.rpc_register();
		Groups.rpc_register();
		UserGroups.rpc_register();
		InterfaceAddresses.rpc_register();
		OsVersion.rpc_register();
		DebPackages.rpc_register();
		AptSources.rpc_register();
		AptExplicitInstall.rpc_register();
		RpmPackages.rpc_register();
		Programs.rpc_register();
		PackageUpdates.rpc_register();
	}

	/**
	 * Register all osquery RPC handlers with ''OLLMrpc''.
	 */
	public static void register()
	{
		OLLMrpc.Request.register("SystemInfo", new SystemInfo());
		OLLMrpc.Request.register("OsVersion", new OsVersion());
		OLLMrpc.Request.register("CpuInfo", new CpuInfo());
		OLLMrpc.Request.register("Uptime", new Uptime());
		OLLMrpc.Request.register("Mounts", new Mounts());
		OLLMrpc.Request.register("LoggedInUsers", new LoggedInUsers());
		OLLMrpc.Request.register("Users", new Users());
		OLLMrpc.Request.register("Groups", new Groups());
		OLLMrpc.Request.register("UserGroups", new UserGroups());
		OLLMrpc.Request.register("InterfaceAddresses", new InterfaceAddresses());
		OLLMrpc.Request.register("DebPackages", new DebPackages());
		OLLMrpc.Request.register("RpmPackages", new RpmPackages());
		OLLMrpc.Request.register("Programs", new Programs());
	}

}
