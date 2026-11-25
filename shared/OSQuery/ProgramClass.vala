/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Argus.Shared.OSQuery
{
	/**
	 * One software-tab category.
	 *
	 * Not a ''programs'' row. The agent sync does not write this
	 * table. {@link ref} is the source, a newline, and the name.
	 * {@link rating} is a {@link Rating} number.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Shared.OSQuery.ProgramClass.init_db(db);
	 * }}}
	 */
	public class ProgramClass : GLib.Object
	{
		/**
		 * Category stored for one software-tab row.
		 *
		 * The number is ''program_class.rating''. Zero is not stored.
		 * A row with no ''program_class'' entry has no category.
		 */
	 
		public enum Rating
		{
			SYSTEM = 1,
			INSTALLED = 2,
			UNKNOWN = 3,
			BAD = 4;

			/**
			 * Set the icon properties on ''target''.
			 *
			 * Writes ''icon-name'', ''tooltip-text'', ''visible'',
			 * and ''css-classes''. Zero clears the icon.
			 *
			 * @param target object that shows the category
			 */
			public void show(Object target)
			{
				var icon_value = Value(typeof(string));
				var tip_value = Value(typeof(string));
				var shown = Value(typeof(bool));
				var classes = Value(typeof(string[]));
				icon_value.set_string("");
				tip_value.set_string("");
				shown.set_boolean(false);
				var current = Value(typeof(string[]));
				target.get_property("css-classes", ref current);
				string[] next = {};
				var existing = (string[]) current.get_boxed();
				if (existing != null) {
					foreach (unowned string item in existing) {
						if (item.has_prefix("program-")) {
							continue;
						}
						next += item;
					}
				}
				switch (this) {
					case SYSTEM:
						icon_value.set_string("applications-system-symbolic");
						tip_value.set_string("System - included with Windows");
						shown.set_boolean(true);
						next += "program-system";
						break;

					case INSTALLED:
						icon_value.set_string("object-select-symbolic");
						tip_value.set_string("Keep - regular application");
						shown.set_boolean(true);
						next += "program-installed";
						break;

					case UNKNOWN:
						icon_value.set_string("weather-clear-symbolic");
						tip_value.set_string("Unknown - need to check");
						shown.set_boolean(true);
						next += "program-unknown";
						break;

					case BAD:
						icon_value.set_string("face-devilish-symbolic");
						tip_value.set_string("Bad - this should probably be removed");
						shown.set_boolean(true);
						next += "program-bad";
						break;

					default:
						break;
				}
				classes.set_boxed(next);
				target.set_property("icon-name", icon_value);
				target.set_property("tooltip-text", tip_value);
				target.set_property("visible", shown);
				target.set_property("css-classes", classes);
			}
		}

		private static SQ.Database db;

		/**
		 * Create ''program_class''.
		 *
		 * @param database Argus database
		 */
		public static void init_db(SQ.Database database)
		{
			ProgramClass.db = database;
			database.exec("""
				CREATE TABLE IF NOT EXISTS program_class (
					ref     TEXT NOT NULL PRIMARY KEY,
					rating  INTEGER NOT NULL
				);
				""");
		}

		/**
		 * Register ''ProgramClass.classify''.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Request.add_class(
				"ProgramClass", typeof(ProgramClass),
				"classify", "iS"
			);
		}

		/**
		 * Store a software-tab category for the selected rows.
		 *
		 * A controller calls this. ''rating'' is a {@link Rating}
		 * number. Each entry in ''refs'' is the source, a newline,
		 * and the name. That is the software-tab row.
		 *
		 * @param request inbound RPC from a controller
		 * @param rating {@link Rating} value
		 * @param refs one source, newline, and name per selected row
		 */
		[CCode (cname = "argus_shared_os_query_program_class_classify")]
		public void classify(OLLMrpc.Request request, int rating, string[] refs)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (rating != Rating.SYSTEM && rating != Rating.INSTALLED &&
				rating != Rating.UNKNOWN && rating != Rating.BAD) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("Unknown category")
				});
				return;
			}
			var query = new SQ.Query<ProgramClass>(ProgramClass.db, "program_class");
			var stmt = query.selectPrepare("""
				INSERT OR REPLACE INTO program_class (
					ref,
					rating
				) VALUES (
					$ref,
					$rating
				)
				""");
			foreach (var key in refs) {
				if (key == null || key.index_of("\n") < 1) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(
							"The row has no source and name")
					});
					return;
				}
				stmt.reset();
				stmt.clear_bindings();
				stmt.bind_text(stmt.bind_parameter_index("$ref"), key);
				stmt.bind_int(stmt.bind_parameter_index("$rating"), rating);
				string err = null;
				ProgramClass.db.db_mutex.lock();
				if (stmt.step() != Sqlite.DONE) {
					err = ProgramClass.db.db.errmsg();
				}
				ProgramClass.db.db_mutex.unlock();
				if (err != null) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST(err)
					});
					return;
				}
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}
	}
}
