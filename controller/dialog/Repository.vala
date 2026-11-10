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

namespace Argus.Controller.Dialog
{
	/**
	 * Clone dialog for one script repository.
	 *
	 * URL, name, username, password, and key, as a preferences page.
	 * {@link open} clears the fields. Clone stays quiet until a URL
	 * and a password or a key are filled in. Clone calls
	 * {@link Argus.Controller.Store.Repository.save}. A failure while
	 * this dialog is showing is presented here.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.Repository(store);
	 * dialog.open(page);
	 * }}}
	 */
	public class Repository : Adw.PreferencesDialog
	{
		public Argus.Controller.Store.Repository store;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }
		private Adw.EntryRow url_row;
		private Adw.EntryRow name_row;
		private Adw.EntryRow user_row;
		private Adw.PasswordEntryRow pass_row;
		private Adw.EntryRow key_row;
		private Adw.ActionRow go;

		/**
		 * @param store repository list that clones the row
		 */
		public Repository(Argus.Controller.Store.Repository store)
		{
			Object(title: "Clone", search_enabled: false);
			this.store = store;
			this.url_row = new Adw.EntryRow() {
				title = "URL",
				input_purpose = Gtk.InputPurpose.URL
			};
			this.name_row = new Adw.EntryRow() {
				title = "Name"
			};
			this.user_row = new Adw.EntryRow() {
				title = "Username"
			};
			this.pass_row = new Adw.PasswordEntryRow() {
				title = "Password"
			};
			this.key_row = new Adw.EntryRow() {
				title = "Key"
			};
			this.go = new Adw.ActionRow() {
				title = "Clone",
				sensitive = false,
				activatable = true,
				css_classes = { "suggested-action" }
			};
			var fields = new Adw.PreferencesGroup() {
				description = "A password or a private key."
			};
			fields.add(this.url_row);
			fields.add(this.name_row);
			fields.add(this.user_row);
			fields.add(this.pass_row);
			fields.add(this.key_row);
			fields.add(this.go);
			var page = new Adw.PreferencesPage();
			page.add(fields);
			this.add(page);
			this.closed.connect(() => {
				this.showing = false;
			});
			this.url_row.changed.connect(() => {
				this.refresh();
			});
			this.pass_row.changed.connect(() => {
				this.refresh();
			});
			this.key_row.changed.connect(() => {
				this.refresh();
			});
			this.store.failed.connect((heading, message) => {
				if (!this.showing) {
					return;
				}
				this.refresh();
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.store.saved.connect(() => {
				if (!this.showing) {
					return;
				}
				this.close();
			});
			this.go.activated.connect(() => {
				if (this.store.busy || !this.go.sensitive) {
					return;
				}
				var url = this.url_row.text.strip();
				var key_text = this.key_row.text.strip();
				var row = new Argus.Shared.SQT.ScriptRepository() {
					url = url,
					name = this.name_row.text.strip(),
					username = this.user_row.text.strip(),
					password = this.pass_row.text,
					key = key_text
				};
				this.go.sensitive = false;
				this.store.save(row);
			});
		}

		/**
		 * Clone stays quiet until a URL and a password or a key are set.
		 */
		private void refresh()
		{
			if (this.store.busy) {
				this.go.sensitive = false;
				return;
			}
			var key_text = this.key_row.text.strip();
			this.go.sensitive = this.url_row.text.strip() != "" &&
				(this.pass_row.text != "" || key_text != "");
		}

		/**
		 * Clear the fields and present the dialog.
		 *
		 * @param parent widget the dialog is shown over
		 */
		public void open(Gtk.Widget parent)
		{
			if (this.showing) {
				return;
			}
			this.url_row.text = "";
			this.name_row.text = "";
			this.user_row.text = "";
			this.pass_row.text = "";
			this.key_row.text = "";
			this.refresh();
			this.showing = true;
			this.present(parent);
			this.url_row.grab_focus();
		}
	}
}
