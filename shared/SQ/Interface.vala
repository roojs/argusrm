/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 */

namespace SQ
{
	/**
	 * Required contract for rows stored with ''SQ.Query''.
	 */
	public interface Interface : GLib.Object
	{
		public virtual string autoincrement_column()
		{
			return "id";
		}
	}
}
