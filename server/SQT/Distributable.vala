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
	 * Installers the controller can list and archive.
	 *
	 * Extends {@link Argus.Shared.SQT.Distributable}. {@link list} is one
	 * live product per row, with the latest version and file size.
	 * {@link archive} sets ''deleted_dt'' so the row leaves that list.
	 * {@link begin}, {@link chunk}, and {@link complete} reassemble an
	 * upload under ''packages/distributables/incoming/''. {@link complete}
	 * reads the installer, moves it to
	 * ''packages/distributables/{sha256}.exe'', and stores the row.
	 *
	 * == Example ==
	 *
	 * {{{
	 * Argus.Server.SQT.Distributable.rpc_register();
	 * OLLMrpc.Request.register("Distributable",
	 *     new Argus.Server.SQT.Distributable.for_rpc(app));
	 * }}}
	 */
	public class Distributable : Argus.Shared.SQT.Distributable
	{
		/**
		 * Server that owns the database.
		 */
		public Application app { get; private set; }
		private Gee.HashMap<int, UploadSession> uploads {
			get; set; default = new Gee.HashMap<int, UploadSession>();
		}
		/**
		 * Added to the unix time in {@link begin} so two uploads in the
		 * same second do not share an id.
		 */
		private int upload_seq = 0;

		/**
		 * Empty instance for the decoder.
		 */
		public Distributable()
		{
			Object();
		}

		/**
		 * Handler singleton.
		 *
		 * @param app the running server
		 */
		public Distributable.for_rpc(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Register the row type and the distributable calls.
		 */
		public static new void rpc_register()
		{
			Argus.Shared.SQT.Distributable.rpc_register();
			OLLMrpc.Request.add_class(
				"Distributable", typeof(Distributable),
				"list", "",
				"archive", "i",
				"begin", "sx",
				"chunk", "ixay",
				"complete", "i",
				"cancel", "i"
			);
		}

		/**
		 * Live products, each with its latest version and file size.
		 *
		 * A deleted product is absent. Osquery in the package store is
		 * not a row here.
		 *
		 * @param request inbound RPC from a controller
		 */
		public void list(OLLMrpc.Request request)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
			Argus.Shared.SQT.Distributable.query(this.app.db).selectQuery("""
				SELECT
					distributable.id,
					distributable.name,
					distributable.platform,
					distributable.added_dt,
					distributable.updated_dt,
					distributable.deleted_dt,
					COALESCE((
						SELECT
							distributable_version.version
						FROM
							distributable_version
						WHERE
							distributable_version.distributable_id = distributable.id
						AND
							distributable_version.deleted_dt = 0
						ORDER BY
							distributable_version.id DESC
						LIMIT
							1
					), '') AS version,
					COALESCE((
						SELECT
							distributable_version.size
						FROM
							distributable_version
						WHERE
							distributable_version.distributable_id = distributable.id
						AND
							distributable_version.deleted_dt = 0
						ORDER BY
							distributable_version.id DESC
						LIMIT
							1
					), 0) AS size,
					COALESCE((
						SELECT
							distributable_version.id
						FROM
							distributable_version
						WHERE
							distributable_version.distributable_id = distributable.id
						AND
							distributable_version.deleted_dt = 0
						ORDER BY
							distributable_version.id DESC
						LIMIT
							1
					), 0) AS version_id
				FROM
					distributable
				WHERE
					distributable.deleted_dt = 0
				ORDER BY
					distributable.name
				""", rows);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", rows),
				msg = "ok"
			});
		}

		/**
		 * Soft-delete one product so {@link list} hides it.
		 *
		 * @param request inbound RPC from a controller
		 * @param id ''distributable.id''
		 */
		public void archive(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var rows = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
			var binds = new Gee.HashMap<string, int>();
			binds.set("id", id);
			Argus.Shared.SQT.Distributable.query(this.app.db).selectWhere(
				"WHERE id = $id AND deleted_dt = 0", binds, null, rows);
			if (rows.size == 0) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("unknown distributable")
				});
				return;
			}
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			rows.get(0).deleted_dt = now;
			rows.get(0).updated_dt = now;
			Argus.Shared.SQT.Distributable.query(this.app.db).updateById(rows.get(0));
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Open a temporary file for one upload.
		 *
		 * The reply id is only in memory. The bytes land in
		 * ''packages/distributables/incoming/{id}''. {@link uploaded_by}
		 * on the session is the calling agent, or ''0'' on the Unix socket.
		 *
		 * @param request inbound RPC from a controller
		 * @param filename name chosen in the file dialog
		 * @param size file length in bytes
		 */
		public void begin(OLLMrpc.Request request, string filename, int64 size)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var name = filename.strip();
			if (name == "" || name.contains("/") || name.contains("\\") || size < 1) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid upload")
				});
				return;
			}
			this.upload_seq++;
			var id = (int) new GLib.DateTime.now_utc().to_unix() + this.upload_seq;
			var dir = GLib.Path.build_filename(
				Argus.SERVER_DATA_DIR, "packages", "distributables", "incoming");
			if (GLib.DirUtils.create_with_parents(dir, 0700) != 0 &&
				!GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR)) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("upload directory failed")
				});
				return;
			}
			var path = GLib.Path.build_filename(dir, id.to_string());
			var session = new UploadSession() {
				id = id,
				filename = name,
				size = size,
				uploaded_by = Argus.Shared.Agent.user(request).id,
				path = path
			};
			try {
				session.stream = GLib.File.new_for_path(path).create(
					GLib.FileCreateFlags.PRIVATE);
			} catch (GLib.Error e) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(e.message)
				});
				return;
			}
			this.uploads.set(id, session);
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("i", id),
				msg = "ok"
			});
		}

		/**
		 * Append one slice of an upload opened by {@link begin}.
		 *
		 * @param request inbound RPC from a controller
		 * @param id upload id
		 * @param offset bytes already stored
		 * @param bytes the next slice, at most 1 MiB
		 */
		public void chunk(OLLMrpc.Request request, int id, int64 offset, uint8[] bytes)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var session = this.uploads.get(id);
			if (session == null || offset != session.received || bytes.length < 1 ||
				bytes.length > 1024 * 1024 ||
				session.received + bytes.length > session.size) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("invalid chunk")
				});
				return;
			}
			try {
				size_t written;
				session.stream.write_all(bytes, out written);
			} catch (GLib.Error e) {
				this.drop_upload(session);
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(e.message)
				});
				return;
			}
			session.received += (int64) bytes.length;
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * The last slice is in. Read the installer and store it.
		 *
		 * The reply is the ''distributable'' row, with ''version'',
		 * ''size'', and ''version_id'' from the file just stored.
		 * A file that is not an NSIS installer, or that has no product
		 * name and version, is deleted and the reply is an error.
		 *
		 * @param request inbound RPC from a controller
		 * @param id upload id
		 */
		public void complete(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var session = this.uploads.get(id);
			if (session == null || session.received != session.size) {
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST("incomplete upload")
				});
				return;
			}
			try {
				session.stream.close();
			} catch (GLib.Error e) {
				this.drop_upload(session);
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(e.message)
				});
				return;
			}
			session.stream = null;
			this.uploads.unset(id);
			Argus.Shared.SQT.Distributable row;
			try {
				row = this.from_file(session);
			} catch (InstallerError e) {
				if (session.path != "") {
					GLib.FileUtils.remove(session.path);
				}
				request.reply(new OLLMrpc.Response() {
					error = new OLLMrpc.Error.INVALID_REQUEST(e.message)
				});
				return;
			}
			this.app.db.backupDB();
			request.reply(new OLLMrpc.Response() {
				retval = OLLMrpc.val("o", row),
				msg = "ok"
			});
		}

		/**
		 * Drop a partial upload and delete its file.
		 *
		 * @param request inbound RPC from a controller
		 * @param id upload id
		 */
		public void cancel(OLLMrpc.Request request, int id)
		{
			if (!Argus.Shared.Agent.is_a_controller(request)) {
				return;
			}
			var session = this.uploads.get(id);
			if (session != null) {
				this.drop_upload(session);
			}
			request.reply(new OLLMrpc.Response() {
				msg = "ok"
			});
		}

		/**
		 * Store one finished upload as a distributable.
		 *
		 * The file moves from ''incoming/'' to
		 * ''packages/distributables/{sha256}.exe''. A live product with
		 * this platform and name gains a version. A new name inserts
		 * the product and the version. The same bytes on that product
		 * return the version already stored.
		 *
		 * @param session finished upload
		 * @return the product, with the latest version fields set
		 */
		private Argus.Shared.SQT.Distributable from_file(UploadSession session) throws InstallerError
		{
			var info = new Installer.from_file(session.path);
			if (info.size != session.size) {
				throw new InstallerError.REJECTED("incomplete upload");
			}
			var dir = GLib.Path.build_filename(
				Argus.SERVER_DATA_DIR, "packages", "distributables");
			if (GLib.DirUtils.create_with_parents(dir, 0700) != 0 &&
				!GLib.FileUtils.test(dir, GLib.FileTest.IS_DIR)) {
				throw new InstallerError.REJECTED("could not store the installer");
			}
			var relative = "distributables/" + info.sha256 + ".exe";
			var dest = GLib.Path.build_filename(dir, info.sha256 + ".exe");
			if (GLib.FileUtils.test(dest, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.remove(session.path);
			} else {
				try {
					GLib.File.new_for_path(session.path).move(
						GLib.File.new_for_path(dest), GLib.FileCopyFlags.NONE);
				} catch (GLib.Error e) {
					throw new InstallerError.REJECTED("could not store the installer");
				}
			}
			var db = this.app.db;
			var products = new Gee.ArrayList<Argus.Shared.SQT.Distributable>();
			var text = new Gee.HashMap<string, string>();
			text.set("platform", "windows");
			text.set("name", info.name);
			Argus.Shared.SQT.Distributable.query(db).selectWhere("""
				WHERE
					platform = $platform
				AND
					name = $name
				AND
					deleted_dt = 0
				""", new Gee.HashMap<string, int>(), text, products);
			var now = (int) new GLib.DateTime.now_utc().to_unix();
			Argus.Shared.SQT.Distributable product;
			if (products.size == 0) {
				product = new Argus.Shared.SQT.Distributable() {
					name = info.name,
					platform = "windows",
					added_dt = now,
					updated_dt = now
				};
				Argus.Shared.SQT.Distributable.query(db).insert(product);
			} else {
				product = products.get(0);
				product.updated_dt = now;
				Argus.Shared.SQT.Distributable.query(db).updateById(product);
			}
			var versions = new Gee.ArrayList<Argus.Shared.SQT.DistributableVersion>();
			var ids = new Gee.HashMap<string, int>();
			ids.set("distributable_id", (int) product.id);
			var sha = new Gee.HashMap<string, string>();
			sha.set("sha256", info.sha256);
			Argus.Shared.SQT.DistributableVersion.query(db).selectWhere("""
				WHERE
					distributable_id = $distributable_id
				AND
					sha256 = $sha256
				AND
					deleted_dt = 0
				""", ids, sha, versions);
			Argus.Shared.SQT.DistributableVersion version;
			if (versions.size == 0) {
				version = new Argus.Shared.SQT.DistributableVersion() {
					distributable_id = product.id,
					version = info.version,
					sha256 = info.sha256,
					filename = session.filename,
					path = relative,
					size = info.size,
					uploaded_by = session.uploaded_by,
					added_dt = now,
					updated_dt = now
				};
				Argus.Shared.SQT.DistributableVersion.query(db).insert(version);
			} else {
				version = versions.get(0);
			}
			product.version = version.version;
			product.size = version.size;
			product.version_id = version.id;
			return product;
		}

		/**
		 * Close and delete a partial upload.
		 *
		 * @param session open upload
		 */
		private void drop_upload(UploadSession session)
		{
			this.uploads.unset(session.id);
			if (session.stream != null) {
				try {
					session.stream.close();
				} catch (GLib.Error e) {
					GLib.warning("%s", e.message);
				}
				session.stream = null;
			}
			if (session.path != "") {
				GLib.FileUtils.remove(session.path);
			}
		}
	}

	/**
	 * One installer upload still in memory.
	 *
	 * The bytes are the file at {@link path}. {@link uploaded_by} is
	 * the controller agent, or ''0'' for the Unix socket.
	 */
	private class UploadSession : GLib.Object
	{
		public int id { get; set; default = 0; }
		public string filename { get; set; default = ""; }
		public int64 size { get; set; default = 0; }
		public int64 received { get; set; default = 0; }
		public int64 uploaded_by { get; set; default = 0; }
		public string path { get; set; default = ""; }
		public GLib.FileOutputStream? stream { get; set; default = null; }
	}
}
