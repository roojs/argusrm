/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * Client-only compatibility for shared SQLite row classes.
 *
 * The server compiles those classes against libocsqlite instead.
 */
namespace Sqlite
{
	public const int OK = 0;

	public delegate int ExecCallback(
		int columns,
		string?[] values,
		string?[] names
	);
}

namespace SQ
{
	public class Database : GLib.Object
	{
		public DatabaseHandle db { get; private set; default = new DatabaseHandle(); }
	}

	public class DatabaseHandle : GLib.Object
	{
		public int exec(
			string sql,
			Sqlite.ExecCallback? callback,
			out string errmsg
		) {
			errmsg = "";
			return Sqlite.OK;
		}

		public string errmsg()
		{
			return "";
		}
	}

	public class Query<T> : GLib.Object
	{
		public Query(Database db, string table)
		{
		}

		public int64 insert(T row)
		{
			return 0;
		}

		public bool updateOld(T old, T newer)
		{
			return false;
		}

		public void deleteId(int64 id)
		{
		}

		public void selectWhere(string where, Gee.HashMap<string, int> int_binds, Gee.HashMap<string, string>? text_binds, Gee.ArrayList<T> rows)
		{
		}

		public void deleteWhere(string where, Gee.HashMap<string, int> int_binds, Gee.HashMap<string, string>? text_binds)
		{
		}
	}
}
