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

namespace Argus.Server.SQT
{
	/**
	 * Server-side script library and filesystem tree scanner.
	 *
	 * The RPC methods create and edit files in ''scripts/'', read and list
	 * files from that library or a clone, and manage machine enablement.
	 * {@link scan} replaces the rows for one script
	 * repository with files found below a directory. Executable files are
	 * scripts. Other files are retained as ordinary files. Hidden
	 * directories and symbolic-link directories are not traversed.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQT.Script.rpc_register();
	 * OLLMrpc.Request.register("Script",
	 *     new Argus.Server.SQT.Script.for_rpc(app));
	 * }}}
	 */
	public class Script : Argus.Shared.SQT.Script
	{
		/**
		 * Database that owns the script rows.
		 */
		public SQ.Database db { get; private set; }

		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public Script()
		{
			Object();
		}

		/**
		 * Create a scanner for one script repository.
		 *
		 * @param db database that owns the script rows
		 * @param repository_id script repository id, or 0 for scripts/
		 */
		public Script.for_repository(SQ.Database db, int64 repository_id)
		{
			Object();
			this.db = db;
			this.script_repository_id = repository_id;
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public Script.for_rpc(Application app)
		{
			Object();
			this.app = app;
			this.db = app.db;
		}

		/**
		 * Register the row types and script calls.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQT.Script.rpc_register();
			Argus.Shared.SQT.ScriptAgent.rpc_register();
			OLLMrpc.Request.add_class(
				"Script", typeof(Script),
				"create", "ss",
				"update", "is",
				"read", "i",
				"list", "i",
				"enable", "ii",
				"disable", "ii",
				"agents", "i"
			);
		}

		/**
		 * Create a file below ''scripts/'' and commit it.
		 *
		 * @param request inbound RPC from the controller
		 * @param path relative path below ''scripts/''
		 * @param body file contents
		 */
		public void create(OLLMrpc.Request request, string path, string body)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (path == "" || GLib.Path.is_absolute(path)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid path")
				});
				return;
			}
			foreach (var part in path.split("/")) {
				if (part != "" && part != "." && part != "..") {
					continue;
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid path")
				});
				return;
			}
			var scripts_dir = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			var parent = scripts_dir;
			var parts = path.split("/");
			for (var i = 0; i < parts.length - 1; i++) {
				parent = GLib.Path.build_filename(parent, parts[i]);
				if (!GLib.FileUtils.test(parent, GLib.FileTest.IS_SYMLINK)) {
					continue;
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid path")
				});
				return;
			}
			var full_path = GLib.Path.build_filename(scripts_dir, path);
			if (GLib.FileUtils.test(full_path, GLib.FileTest.EXISTS)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("already exists")
				});
				return;
			}
			if (GLib.DirUtils.create_with_parents(GLib.Path.get_dirname(full_path), 0755) != 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR("could not create directory")
				});
				return;
			}
			try {
				GLib.FileUtils.set_contents(full_path, body);
				GLib.FileUtils.chmod(full_path, 0755);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			try {
				var repository = Ggit.Repository.open(GLib.File.new_for_path(scripts_dir));
				var index = repository.get_index();
				index.add_path(path);
				index.write();
				var tree = repository.lookup_tree(index.write_tree());
				var signature = new Ggit.Signature.now("Argus", "argus@localhost");
				Ggit.Commit[] parents = {};
				if (!repository.is_empty()) {
					parents += repository.get_head().lookup() as Ggit.Commit;
				}
				repository.create_commit("HEAD", signature, signature, null,
					"Create " + path, tree, parents);
			} catch (GLib.Error e) {
				GLib.FileUtils.remove(full_path);
				try {
					var repository = Ggit.Repository.open(GLib.File.new_for_path(scripts_dir));
					var index = repository.get_index();
					index.remove(GLib.File.new_for_path(path), 0);
					index.write();
				} catch (GLib.Error rollback_error) {
					GLib.warning("could not restore index: %s", rollback_error.message);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			this.script_repository_id = 0;
			this.scan(scripts_dir);
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var int_binds = new Gee.HashMap<string, int>();
			var text_binds = new Gee.HashMap<string, string>();
			int_binds.set("script_repository_id", 0);
			text_binds.set("path", path);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE script_repository_id = $script_repository_id AND path = $path",
				int_binds, text_binds, rows);
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
		}

		/**
		 * Replace a local script file and commit it.
		 *
		 * @param request inbound RPC from the controller
		 * @param id ''script.id''
		 * @param body replacement file contents
		 */
		public void update(OLLMrpc.Request request, int id, string body)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id AND script_repository_id = 0", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown local script")
				});
				return;
			}
			var scripts_dir = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			var full_path = GLib.Path.build_filename(scripts_dir, rows.get(0).path);
			if (GLib.FileUtils.test(full_path, GLib.FileTest.IS_SYMLINK)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid path")
				});
				return;
			}
			try {
				GLib.FileUtils.set_contents(full_path, body);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			try {
				var repository = Ggit.Repository.open(GLib.File.new_for_path(scripts_dir));
				var index = repository.get_index();
				index.add_path(rows.get(0).path);
				index.write();
				var tree = repository.lookup_tree(index.write_tree());
				var signature = new Ggit.Signature.now("Argus", "argus@localhost");
				Ggit.Commit[] parents = { repository.get_head().lookup() as Ggit.Commit };
				repository.create_commit("HEAD", signature, signature, null,
					"Update " + rows.get(0).path, tree, parents);
			} catch (GLib.Error e) {
				try {
					var repository = Ggit.Repository.open(GLib.File.new_for_path(scripts_dir));
					string[] paths = { rows.get(0).path };
					repository.reset_default(repository.get_head().lookup(), paths);
					var options = new Ggit.CheckoutOptions();
					options.set_strategy(Ggit.CheckoutStrategy.FORCE);
					options.set_paths(paths);
					repository.checkout_index(null, options);
				} catch (GLib.Error restore_error) {
					GLib.warning("could not restore %s: %s", full_path, restore_error.message);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
		}

		/**
		 * Read one script or ordinary library file.
		 *
		 * @param request inbound RPC from the controller
		 * @param id ''script.id''
		 */
		public void read(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere("WHERE id = $id", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown script")
				});
				return;
			}
			var root = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "scripts");
			if (rows.get(0).script_repository_id > 0) {
				var repositories = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
				var repository_binds = new Gee.HashMap<string, int>();
				repository_binds.set("id", (int) rows.get(0).script_repository_id);
				Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere("WHERE id = $id", 
						repository_binds, null, repositories);

				if (repositories.size == 0) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown repository")
					});
					return;
				}
				root = GLib.Path.build_filename(
					Argus.SERVER_DATA_DIR, "git", repositories.get(0).name);
			}
			var full_path = GLib.Path.build_filename(root, rows.get(0).path);
			if (GLib.FileUtils.test(full_path, GLib.FileTest.IS_SYMLINK)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid path")
				});
				return;
			}
			var body = "";
			try {
				GLib.FileUtils.get_contents(full_path, out body);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("s", body),
				msg = "ok"
			});
		}

		/**
		 * List files from one script repository.
		 *
		 * @param request inbound RPC from the controller
		 * @param repository_id repository id, or 0 for ''scripts/''
		 */
		public void list(OLLMrpc.Request request, int repository_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_repository_id", repository_id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere("WHERE script_repository_id = $script_repository_id",
						binds, null, rows);

			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Enable a script on one machine.
		 *
		 * @param request inbound RPC from the controller
		 * @param script_id ''script.id''
		 * @param agent_id ''agent.id''
		 */
		public void enable(OLLMrpc.Request request, int script_id, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var script_binds = new Gee.HashMap<string, int>();
			script_binds.set("id", script_id);
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE id = $id AND filetype = 'script'", script_binds, null, scripts);

			var machine_rows = new Gee.ArrayList<Argus.Shared.Agent>();
			var agent_binds = new Gee.HashMap<string, int>();
			agent_binds.set("id", agent_id);
			Argus.Shared.Agent.query(this.app.db).selectWhere(
				"WHERE id = $id AND status = 1", agent_binds, null, machine_rows);

			if (scripts.size == 0 || machine_rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown script or agent")
				});
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			binds.set("agent_id", agent_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere(
				"WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null, rows);

			if (rows.size == 0) {
				var row = new Argus.Shared.SQT.ScriptAgent() {
					script_id = script_id,
					agent_id = agent_id
				};
				Argus.Shared.SQT.ScriptAgent.query(this.app.db).insert(row);
				rows.add(row);
				this.app.db.backupDB();
			}
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows.get(0)),
				msg = "ok"
			});
		}

		/**
		 * Disable a script on one machine.
		 *
		 * @param request inbound RPC from the controller
		 * @param script_id ''script.id''
		 * @param agent_id ''agent.id''
		 */
		public void disable(OLLMrpc.Request request, int script_id, int agent_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			binds.set("agent_id", agent_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).deleteWhere("WHERE script_id = $script_id AND agent_id = $agent_id",
				binds, null);

			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * List machines on which a script is enabled.
		 *
		 * @param request inbound RPC from the controller
		 * @param script_id ''script.id''
		 */
		public void agents(OLLMrpc.Request request, int script_id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptAgent>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_id", script_id);
			Argus.Shared.SQT.ScriptAgent.query(this.app.db).selectWhere("WHERE script_id = $script_id", binds, null, rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Replace this repository's script rows from a filesystem tree.
		 *
		 * @param root root directory to scan
		 */
		public void scan(string root)
		{
			var binds = new Gee.HashMap<string, int>();
			binds.set("script_repository_id", (int) this.script_repository_id);
			var old_scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			var query = Argus.Shared.SQT.Script.query(this.db);
			query.selectWhere("WHERE script_repository_id = $script_repository_id", binds, null, old_scripts);
			var old_paths = new Gee.HashMap<string, Argus.Shared.SQT.Script>();
			foreach (var old_script in old_scripts) {
				old_paths.set(old_script.path, old_script);
			}

			var new_scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			this.walk(root, "", new_scripts);
			foreach (var new_script in new_scripts) {
				if (!old_paths.has_key(new_script.path)) {
					query.insert(new_script);
					continue;
				}
				var old_script = old_paths.get(new_script.path);
				old_paths.unset(new_script.path);
				if (old_script.filetype == new_script.filetype) {
					continue;
				}
				old_script.filetype = new_script.filetype;
				query.updateById(old_script);
			}

			foreach (var old_script in old_paths.values) {
				query.deleteId(old_script.id);
			}
		}

		/**
		 * Walk one directory below the scan root.
		 *
		 * @param root root directory used for stored relative paths
		 * @param relative directory below root, or empty for root
		 * @param scripts rows found below root
		 */
		private void walk(string root, string relative, Gee.ArrayList<Argus.Shared.SQT.Script> scripts)
		{
			var directory = relative == "" ? root : GLib.Path.build_filename(root, relative);
			try {
				var opened = GLib.Dir.open(directory);
				var child = "";
				while ((child = opened.read_name()) != null) {
					var child_relative = relative == "" ? child : GLib.Path.build_filename(relative, child);
					var child_path = GLib.Path.build_filename(root, child_relative);
					if (child.has_prefix(".")) {
						continue;
					}
					if (!GLib.FileUtils.test(child_path, GLib.FileTest.IS_DIR) ||
						GLib.FileUtils.test(child_path, GLib.FileTest.IS_SYMLINK)) {
						scripts.add(new Argus.Shared.SQT.Script() {
							script_repository_id = this.script_repository_id,
							path = child_relative,
							filetype = GLib.FileUtils.test(child_path, GLib.FileTest.IS_EXECUTABLE) ? "script" : "file"
						});
						continue;
					}
					
					this.walk(root, child_relative, scripts);
				}
			} catch (GLib.Error e) {
				GLib.warning("could not scan %s: %s", directory, e.message);
			}
		}
	}
}
