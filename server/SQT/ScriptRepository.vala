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
	 * Git clones under ''git/''.
	 *
	 * Extends the {@link Argus.Shared.SQT.ScriptRepository} row.
	 * {@link clone} uses libgit2, then writes the row. {@link pull}
	 * fetches and refreshes {@link Argus.Shared.SQT.Script} rows.
	 * {@link remove} deletes the checkout. {@link list} is the clones,
	 * not ''scripts/''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQT.ScriptRepository.rpc_register();
	 * OLLMrpc.Request.register("ScriptRepository",
	 *     new Argus.Server.SQT.ScriptRepository.for_rpc(app));
	 * }}}
	 */
	public class ScriptRepository : Argus.Shared.SQT.ScriptRepository
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }

		/**
		 * Empty instance for the decoder.
		 */
		public ScriptRepository()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public ScriptRepository.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Delete a directory and everything below it.
		 *
		 * Symbolic links are deleted instead of traversed. A directory
		 * that cannot be opened is left for its parent removal attempt.
		 *
		 * @param path directory to delete
		 */
		private void delete_directory(string path)
		{
			try {
				var opened = GLib.Dir.open(path);
				var child = "";
				while ((child = opened.read_name()) != null) {
					var child_path = GLib.Path.build_filename(path, child);
					if (GLib.FileUtils.test(child_path, GLib.FileTest.IS_DIR) &&
						!GLib.FileUtils.test(child_path, GLib.FileTest.IS_SYMLINK)) {
						this.delete_directory(child_path);
						continue;
					}
					GLib.FileUtils.remove(child_path);
				}
			} catch (GLib.Error open_error) {
				return;
			}
			GLib.DirUtils.remove(path);
		}

		/**
		 * Register the row types and the repository calls.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQT.ScriptRepository.rpc_register();
			Argus.Shared.SQT.Script.rpc_register();
			OLLMrpc.Request.add_class(
				"ScriptRepository", typeof(ScriptRepository),
				"clone", "o",
				"pull", "i",
				"remove", "i",
				"list", ""
			);
		}

		/**
		 * Clone a URL into ''git/{name}'', then insert the row.
		 *
		 * The checkout must succeed before the database row exists.
		 * Empty ''name'' uses the last part of the URL. Username and
		 * password, or a key.
		 *
		 * @param request inbound RPC from the controller
		 * @param row URL, optional alias, and credentials
		 */
		public void clone(OLLMrpc.Request request, Argus.Shared.SQT.ScriptRepository row)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			if (row.url == "") {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("url required")
				});
				return;
			}
			if (row.password == "" && row.key == "") {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("password or key required")
				});
				return;
			}
			if (row.name == "") {
				row.name = GLib.Path.get_basename(row.url);
				if (row.name.has_suffix(".git")) {
					row.name = row.name.substring(0, row.name.length - 4);
				}
			}
			if (row.name == "" || row.name == "." || row.name == ".." || row.name.contains("/")) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("invalid name")
				});
				return;
			}
			var dest = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "git", row.name);
			if (GLib.FileUtils.test(dest, GLib.FileTest.EXISTS)) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("already exists")
				});
				return;
			}
			var callbacks = new Argus.Server.Git.Callbacks() {
				username = row.username,
				password = row.password
			};
			var key_path = dest + ".key";
			var previous_ssh = GLib.Environment.get_variable("GIT_SSH_COMMAND");
			if (row.key != "") {
				try {
					GLib.FileUtils.set_contents(key_path, row.key);
					GLib.FileUtils.chmod(key_path, 0600);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
					});
					return;
				}
				GLib.Environment.set_variable("GIT_SSH_COMMAND",
					"ssh -i " + key_path + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new", true);
			}
			var options = new Ggit.CloneOptions();
			var fetch = new Ggit.FetchOptions();
			fetch.set_remote_callbacks(callbacks);
			options.set_fetch_options(fetch);
			var repo = (Ggit.Repository) null;
			try {
				repo = Ggit.Repository.clone(row.url, GLib.File.new_for_path(dest), options);
			} catch (GLib.Error e) {
				// clone failed... - cleanup...
				if (previous_ssh == null) {
					GLib.Environment.unset_variable("GIT_SSH_COMMAND");
				}
				if (previous_ssh != null) {
					GLib.Environment.set_variable("GIT_SSH_COMMAND", previous_ssh, true);
				}
				if (GLib.FileUtils.test(dest, GLib.FileTest.EXISTS)) {
					this.delete_directory(dest);
				}
				if (GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
					GLib.FileUtils.remove(key_path);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			if (previous_ssh == null) {
				GLib.Environment.unset_variable("GIT_SSH_COMMAND");
			}
			if (previous_ssh != null) {
				GLib.Environment.set_variable("GIT_SSH_COMMAND", previous_ssh, true);
			}
			if (repo == null) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("clone failed")
				});
				return;
			}
			Argus.Shared.SQT.ScriptRepository.query(this.app.db).insert(row);
			new Script.for_repository(this.app.db, row.id).scan(dest);
			this.app.db.backupDB();
			GLib.debug("cloned %s", dest);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", row),
				msg = "ok"
			});
		}

		/**
		 * Fetch a clone and refresh its ''script'' rows.
		 *
		 * @param request inbound RPC from the controller
		 * @param id ''script_repository.id''
		 */
		public void pull(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
			var id_binds = new Gee.HashMap<string, int>();
			id_binds.set("id", id);
			Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere(
				"WHERE id = $id", id_binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown repository")
				});
				return;
			}
			var row = rows.get(0);
			var dest = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "git", row.name);
			var callbacks = new Argus.Server.Git.Callbacks() {
				username = row.username,
				password = row.password
			};
			var key_path = dest + ".key";
			var previous_ssh = GLib.Environment.get_variable("GIT_SSH_COMMAND");
			if (row.key != "") {
				try {
					GLib.FileUtils.set_contents(key_path, row.key);
					GLib.FileUtils.chmod(key_path, 0600);
				} catch (GLib.Error e) {
					request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
					});
					return;
				}
				GLib.Environment.set_variable("GIT_SSH_COMMAND",
					"ssh -i " + key_path + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new", true);
			}
			var repo = (Ggit.Repository) null;
			try {
				repo = Ggit.Repository.open(GLib.File.new_for_path(dest));
			} catch (GLib.Error e) {
				if (previous_ssh == null) {
					GLib.Environment.unset_variable("GIT_SSH_COMMAND");
				}
				if (previous_ssh != null) {
					GLib.Environment.set_variable("GIT_SSH_COMMAND", previous_ssh, true);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			try {
				var remote = repo.lookup_remote("origin");
				var fetch = new Ggit.FetchOptions();
				fetch.set_remote_callbacks(callbacks);
				remote.connect(Ggit.Direction.FETCH, callbacks, null, null);
				remote.download(null, fetch);
				remote.update_tips(callbacks, true, Ggit.RemoteDownloadTagsType.UNSPECIFIED, null);
				remote.disconnect();
			} catch (GLib.Error e) {
				if (previous_ssh == null) {
					GLib.Environment.unset_variable("GIT_SSH_COMMAND");
				}
				if (previous_ssh != null) {
					GLib.Environment.set_variable("GIT_SSH_COMMAND", previous_ssh, true);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			if (previous_ssh == null) {
				GLib.Environment.unset_variable("GIT_SSH_COMMAND");
			}
			if (previous_ssh != null) {
				GLib.Environment.set_variable("GIT_SSH_COMMAND", previous_ssh, true);
			}
			var short_name = "";
			try {
				var head_name = repo.get_head().get_name();
				short_name = head_name;
				if (head_name.has_prefix("refs/heads/")) {
					short_name = head_name.substring(11);
				}
			} catch (GLib.Error e) {
				short_name = "";
			}
			var remote_ref = (Ggit.Ref) null;
			if (short_name != "") {
				try {
					remote_ref = repo.lookup_reference("refs/remotes/origin/" + short_name);
				} catch (GLib.Error e) {
					remote_ref = null;
				}
			}
			if (remote_ref == null) {
				try {
					remote_ref = repo.lookup_reference("refs/remotes/origin/master");
				} catch (GLib.Error e) {
					remote_ref = null;
				}
			}
			if (remote_ref == null) {
				try {
					remote_ref = repo.lookup_reference("refs/remotes/origin/main");
				} catch (GLib.Error e) {
					remote_ref = null;
				}
			}
			if (remote_ref == null) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INTERNAL_ERROR("no origin branch")
				});
				return;
			}
			try {
				var commit = remote_ref.lookup() as Ggit.Commit;
				repo.reset(commit, Ggit.ResetType.HARD, new Ggit.CheckoutOptions());
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INTERNAL_ERROR(e.message)
				});
				return;
			}
			new Script.for_repository(this.app.db, row.id).scan(dest);
			var script_binds = new Gee.HashMap<string, int>();
			script_binds.set("script_repository_id", (int) row.id);
			var scripts = new Gee.ArrayList<Argus.Shared.SQT.Script>();
			Argus.Shared.SQT.Script.query(this.app.db).selectWhere(
				"WHERE script_repository_id = $script_repository_id", script_binds, null, scripts);
			this.app.db.backupDB();
			GLib.debug("pulled %s", dest);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", scripts),
				msg = "ok"
			});
		}

		/**
		 * Delete a clone, its ''script'' rows, and the repository row.
		 *
		 * @param request inbound RPC from the controller
		 * @param id ''script_repository.id''
		 */
		public void remove(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
			var id_binds = new Gee.HashMap<string, int>();
			id_binds.set("id", id);
			Argus.Shared.SQT.ScriptRepository.query(this.app.db).selectWhere("WHERE id = $id", id_binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
						error = new OLLMrpc.Error.INVALID_REQUEST("unknown repository")
				});
				return;
			}
			var dest = GLib.Path.build_filename(Argus.SERVER_DATA_DIR, "git", rows.get(0).name);
			if (GLib.FileUtils.test(dest, GLib.FileTest.IS_DIR)) {
				this.delete_directory(dest);
			}
			var key_path = dest + ".key";
			if (GLib.FileUtils.test(key_path, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.remove(key_path);
			}
			var script_binds = new Gee.HashMap<string, int>();
			script_binds.set("script_repository_id", (int) rows.get(0).id);
			Argus.Shared.SQT.Script.query(this.app.db).deleteWhere(
				"WHERE script_repository_id = $script_repository_id", script_binds, null);
			Argus.Shared.SQT.ScriptRepository.query(this.app.db).deleteId(rows.get(0).id);
			this.app.db.backupDB();
			GLib.debug("removed %s", dest);
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * List the clones. Not ''scripts/''.
		 *
		 * @param request inbound RPC from the controller
		 */
		public void list(OLLMrpc.Request request)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.ScriptRepository>();
			Argus.Shared.SQT.ScriptRepository.query(this.app.db).select("", rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}
	}
}
