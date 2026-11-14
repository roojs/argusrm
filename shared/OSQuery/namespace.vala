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
		LoggedInUsers.init_db(db);
		Users.init_db(db);
		Groups.init_db(db);
		UserGroups.init_db(db);
		InterfaceAddresses.init_db(db);
		OsVersion.init_db(db);
		DebPackages.init_db(db);
		RpmPackages.init_db(db);
		Programs.init_db(db);
		PackageUpdates.init_db(db);
	}

}
