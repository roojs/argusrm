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

namespace Argus.Shared.Registration
{
	/**
	 * Local controller registration result.
	 *
	 * The running server returns this object over the Unix RPC connection.
	 * The privileged controller command serializes it to standard output.
	 * {@link deregister} removes the server row for this certificate
	 * on the TLS connection already open, then closes that connection.
	 * If the server does not answer, the dialog can still remove the
	 * keyring secret and the saved connection.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var data = new Argus.Shared.Registration.Data() {
	 *     name = "office-server",
	 *     addresses = { "192.0.2.10" },
	 *     port = 817
	 * };
	 * }}}
	 */
	public class Data : GLib.Object, Json.Serializable, OLLMrpc.Bin.Serializable
	{
		public string error { get; set; default = ""; }
		public string private_key { get; set; default = ""; }
		public string client_certificate { get; set; default = ""; }
		public string ca_certificate { get; set; default = ""; }
		public string name { get; set; default = ""; }
		public string[] addresses { get; set; default = {}; }
		public int port { get; set; default = 0; }

		/**
		 * Deregister finished.
		 *
		 * @param removed true when the saved login was deleted
		 */
		public signal void finished(bool removed);

		private unowned Gtk.Widget deregister_parent;

		/**
		 * Register the local registration result wire type.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Registration.Data", typeof(Data));
		}

		/**
		 * Remove this controller's server row and saved login.
		 *
		 * The call uses the TLS connection already open for this
		 * certificate. The connection closes after the server
		 * answers. The call has five seconds. If it does not answer,
		 * the dialog can still drop the saved login. {@link finished}
		 * reports the outcome. ''name'' selects the saved row.
		 *
		 * @param parent window that presents the dialogs
		 * @param rpc open TLS client for this server
		 */
		public void deregister(Gtk.Widget parent, OLLMrpc.Client rpc)
		{
			this.deregister_parent = parent;
			if (this.client_certificate == "") {
				this.fail("The saved server has no certificate.");
				return;
			}
			GLib.TlsCertificate cert;
			try {
				cert = new GLib.TlsCertificate.from_pem(
					this.client_certificate, this.client_certificate.length);
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
			var fingerprint = GLib.Checksum.compute_for_data(
				GLib.ChecksumType.SHA256, cert.certificate.data);
			if (!rpc.connected) {
				this.offer_local("The server did not answer.");
				return;
			}
			var settled = false;
			uint wait = 0;
			wait = GLib.Timeout.add_seconds(5, () => {
				if (settled) {
					return false;
				}
				settled = true;
				wait = 0;
				this.offer_local("The server did not answer.");
				return false;
			});
			rpc.call.begin(new OLLMrpc.Request() {
				method = "Registration.deregister",
				args = OLLMrpc.args("s", fingerprint)
			}, (call_obj, call_res) => {
				if (settled) {
					return;
				}
				settled = true;
				if (wait != 0) {
					GLib.Source.remove(wait);
					wait = 0;
				}
				var response = new OLLMrpc.Response();
				try {
					response = rpc.call.end(call_res);
				} catch (GLib.Error e) {
					this.offer_local(e.message);
					return;
				}
				if (response.error != null) {
					this.fail(response.error.message);
					return;
				}
				rpc.disconnect();
				this.clear_and_finish();
			});
		}

		/**
		 * Remove this login's keyring secret and saved row.
		 *
		 * Other rows in ''connections.json'' stay. A missing file
		 * or secret is success. ''name'' selects the row.
		 *
		 * @throws GLib.Error the secret or the file could not be updated
		 */
		public void clear_saved_login() throws GLib.Error
		{
#if LINUX
			var types = new GLib.HashTable<string, Secret.SchemaAttributeType>(
				GLib.str_hash, GLib.str_equal);
			types.insert("service", Secret.SchemaAttributeType.STRING);
			types.insert("server", Secret.SchemaAttributeType.STRING);
			types.insert("name", Secret.SchemaAttributeType.STRING);
			var schema = new Secret.Schema.newv("org.roojs.ArgusController",
				Secret.SchemaFlags.NONE, types);
			var attrs = new GLib.HashTable<string, string>(GLib.str_hash, GLib.str_equal);
			attrs.insert("service", "argusrm");
			attrs.insert("name", this.name);
			Secret.password_clearv_sync(schema, attrs, null);
#endif
			var path = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm", "connections.json");
			var kept = new Gee.ArrayList<string>();
			if (GLib.FileUtils.test(path, GLib.FileTest.EXISTS)) {
				var text = "";
				GLib.FileUtils.get_contents(path, out text);
				var parser = new Json.Parser();
				parser.load_from_data(text);
				var root = parser.get_root();
				if (root != null && root.get_node_type() == Json.NodeType.ARRAY) {
					var list = root.get_array();
					var count = list.get_length();
					for (var i = 0; i < (int) count; i++) {
						var element = list.get_element(i);
						if (element.get_node_type() != Json.NodeType.OBJECT) {
							continue;
						}
						var row = element.get_object();
						if (row.has_member("name") && row.get_string_member("name") == this.name) {
							continue;
						}
						var generator = new Json.Generator();
						generator.set_root(element);
						kept.add(generator.to_data(null));
					}
				}
			}
			var json = "[]\n";
			if (kept.size > 0) {
				json = "[\n" + string.joinv(",\n", kept.to_array()) + "\n]\n";
			}
			var dir = GLib.Path.build_filename(
				GLib.Environment.get_user_config_dir(), "argusrm");
			if (GLib.DirUtils.create_with_parents(dir, 0700) != 0) {
				throw new GLib.FileError.FAILED(
					"Could not create the configuration directory");
			}
			GLib.FileUtils.set_contents(path, json);
			GLib.FileUtils.chmod(path, 0600);
		}

		/**
		 * Offer to drop the saved login after the server call stops.
		 *
		 * @param message why the server call stopped
		 */
		private void offer_local(string message)
		{
			this.finished(false);
			var down = new Argus.Shared.Notice("Could not deregister", message);
			down.add_response("cancel", "Cancel");
			down.add_response("local", "Deregister locally");
			down.responded.connect((response) => {
				if (response != "local") {
					return;
				}
				this.clear_and_finish();
			});
			down.present(this.deregister_parent);
		}

		/**
		 * Drop the saved login and report it on OK.
		 */
		private void clear_and_finish()
		{
			try {
				this.clear_saved_login();
			} catch (GLib.Error e) {
				this.fail(e.message);
				return;
			}
			var done = new Argus.Shared.Notice("Deleted okay", "");
			done.add_response("ok", "OK");
			done.closed.connect(() => {
				this.finished(true);
			});
			done.present(this.deregister_parent);
		}

		/**
		 * Show a deregister failure.
		 *
		 * @param message failure text
		 */
		private void fail(string message)
		{
			this.finished(false);
			var failed = new Argus.Shared.Notice("Could not deregister", message);
			failed.add_response("ok", "OK");
			failed.present(this.deregister_parent);
		}
	}
}
