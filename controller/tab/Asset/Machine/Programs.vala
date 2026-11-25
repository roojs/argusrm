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

namespace Argus.Controller.Tab.Asset.Machine
{
	/**
	 * Per-machine Windows program grid in {@link Detail}.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''programs_machine.csv''. {@link Argus.Controller.Store.Programs}
	 * loads ''Programs.list'' for the selected ''agent_id''.
	 * {@link Argus.Controller.Filters.Programs} is the bar above
	 * the grid: search on the left and Filters on the right.
	 * Desktop adds a save icon. It writes this machine's loaded
	 * list to a spreadsheet and opens that file in the
	 * registered spreadsheet application. Android leaves that
	 * icon out. The grid columns follow
	 * ''programs_machine.csv''. The spreadsheet adds the file
	 * hash, the signing result, and the certificate fields.
	 * An empty grid shows a spinner over it while that call is
	 * in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var tab = new Argus.Controller.Tab.Asset.Machine.Programs(window);
	 * tab.load(1);
	 * }}}
	 */
	public class Programs : Argus.Controller.Tab.Base
	{
		private Argus.Controller.Store.Programs store;
		private Argus.Controller.Filters.Programs filter;
#if !ANDROID
		/**
		 * Agent whose list was last requested.
		 */
		private int loaded_agent = 0;
		/**
		 * True while the save dialog or the spreadsheet write
		 * is in progress.
		 */
		private bool exporting = false;
#endif

		/**
		 * Build the per-machine Windows program grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs_machine", "name");
			this.store = new Argus.Controller.Store.Programs(window.app);
			this.filter = new Argus.Controller.Filters.Programs();
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			var task_store = new Argus.Controller.Store.TaskTarget(window.app);
			task_store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			task_store.submitted.connect((count) => {
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			this.remove_confirmed.connect((obj) => {
				var row = obj as Argus.Shared.OSQuery.Programs;
				if (row == null || row.agent_id < 1) {
					return;
				}
				var cmd = row.silent_command();
				if (cmd == "") {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + row.name));
					return;
				}
				var ids = new Gee.ArrayList<int32>();
				ids.add((int32) row.agent_id);
				task_store.run_command("Uninstall " + row.name, cmd, ids);
			});
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
#if !ANDROID
			var save = new Gtk.Button() {
				icon_name = "document-save-symbolic",
				tooltip_text = "Save program list",
				halign = Gtk.Align.END
			};
			save.clicked.connect(() => {
				this.export(window, save);
			});
#endif
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(this.filter.menu());
#if !ANDROID
			bar.append(save);
#endif
			this.content.append(bar);
			this.content.append(this.overlay);
		}

#if !ANDROID
		/**
		 * Ask where to save this machine's program list, write
		 * that spreadsheet, and open it in the registered
		 * spreadsheet application.
		 *
		 * The grid columns follow ''programs_machine.csv''. The
		 * spreadsheet also writes the file hash, the signing
		 * result, and the certificate fields. A click while a
		 * save is already open is ignored. A list that is still
		 * loading shows a toast.
		 *
		 * @param window window that owns the file dialog
		 * @param save the save button, disabled until the write ends
		 */
		private void export(Argus.Controller.Window window, Gtk.Button save)
		{
			if (this.exporting) {
				return;
			}
			if (this.store.busy) {
				this.toasts.add_toast(new Adw.Toast("The program list is still loading"));
				return;
			}
			this.exporting = true;
			save.sensitive = false;
			var stamp = new GLib.DateTime.now_local().format("%Y-%m-%d");
			var chooser = new Gtk.FileDialog() {
				title = "Save program list",
				modal = true,
				initial_name = "Argus-Windows-Programs-" +
					this.loaded_agent.to_string() + "-" + stamp + ".xlsx"
			};
			var xlsx = new Gtk.FileFilter();
			xlsx.set_filter_name("Excel workbook");
			xlsx.add_mime_type("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
			xlsx.add_suffix("xlsx");
			var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
			filters.append(xlsx);
			chooser.filters = filters;
			chooser.default_filter = xlsx;
			chooser.save.begin(window, null, (obj, res) => {
				var path = "";
				try {
					var chosen = chooser.save.end(res);
					if (chosen == null) {
						this.exporting = false;
						save.sensitive = true;
						return;
					}
					var chosen_path = chosen.get_path();
					if (chosen_path == null || chosen_path == "") {
						this.exporting = false;
						save.sensitive = true;
						return;
					}
					path = chosen_path;
				} catch (GLib.Error e) {
					this.exporting = false;
					save.sensitive = true;
					return;
				}
				var book = new Lxw.Workbook(path);
				unowned Lxw.Worksheet sheet = book.add_worksheet("Programs");
				unowned Lxw.Format header = book.add_format();
				header.set_bold();
				sheet.write_string(0, 0, "Source", header);
				sheet.write_string(0, 1, "Name", header);
				sheet.write_string(0, 2, "Version", header);
				sheet.write_string(0, 3, "Scope", header);
				sheet.write_string(0, 4, "Architecture", header);
				sheet.write_string(0, 5, "User", header);
				sheet.write_string(0, 6, "Extra", header);
				sheet.write_string(0, 7, "Publisher", header);
				sheet.write_string(0, 8, "Install date", header);
				sheet.write_string(0, 9, "Language", header);
				sheet.write_string(0, 10, "Identifying number", header);
				sheet.write_string(0, 11, "Install location", header);
				sheet.write_string(0, 12, "Install source", header);
				sheet.write_string(0, 13, "Uninstall string", header);
				sheet.write_string(0, 14, "Uninstall", header);
				sheet.write_string(0, 15, "File SHA-256", header);
				sheet.write_string(0, 16, "Signing result", header);
				sheet.write_string(0, 17, "Certificate SHA-256", header);
				sheet.write_string(0, 18, "Subject key id", header);
				sheet.write_string(0, 19, "Signer", header);
				sheet.write_string(0, 20, "Issuer", header);
				sheet.write_string(0, 21, "Serial", header);
				for (var i = 0; i < this.store.items.size; i++) {
					var line = (uint) (i + 1);
					var program = this.store.items.get(i);
					sheet.write_string(line, 0, program.source);
					sheet.write_string(line, 1, program.name);
					sheet.write_string(line, 2, program.version);
					sheet.write_string(line, 3, program.scope);
					sheet.write_string(line, 4, program.architecture);
					sheet.write_string(line, 5, program.user_account);
					sheet.write_string(line, 6, program.extra);
					sheet.write_string(line, 7, program.publisher);
					sheet.write_string(line, 8, program.install_date);
					sheet.write_string(line, 9, program.language);
					sheet.write_string(line, 10, program.identifying_number);
					sheet.write_string(line, 11, program.install_location);
					sheet.write_string(line, 12, program.install_source);
					sheet.write_string(line, 13, program.uninstall_string);
					sheet.write_number(line, 14, (double) program.uninstall_count);
					sheet.write_string(line, 15, program.file_sha256);
					sheet.write_string(line, 16, program.signing_result);
					sheet.write_string(line, 17, program.signer_cert_sha256);
					sheet.write_string(line, 18, program.signer_subject_key_id);
					sheet.write_string(line, 19, program.signer_publisher);
					sheet.write_string(line, 20, program.signer_issuer);
					sheet.write_string(line, 21, program.signer_serial);
				}
				var last_row = (uint) this.store.items.size;
				sheet.freeze_panes(1, 2);
				sheet.set_autofilter(0, 0, last_row, 21);
				sheet.set_column(0, 21, 18);
				sheet.set_column(1, 1, 36);
				sheet.set_column(15, 15, 66);
				sheet.set_column(17, 18, 66);
				var closed = book.close();
				this.exporting = false;
				save.sensitive = true;
				if (closed != Lxw.Error.NO_ERROR) {
					var notice = new Argus.Shared.Notice(
						"Could not save the program list",
						Lxw.strerror(closed));
					notice.add_response("ok", "OK");
					notice.present(this);
					return;
				}
				var count_label = this.store.items.size == 1 ?
					"1 program" :
					this.store.items.size.to_string() + " programs";
				this.toasts.add_toast(new Adw.Toast("Saved " + count_label));
				var launcher = new Gtk.FileLauncher(GLib.File.new_for_path(path));
				launcher.launch.begin(window, null, (launch_obj, launch_res) => {
					try {
						launcher.launch.end(launch_res);
					} catch (GLib.Error e) {
						var open_notice = new Argus.Shared.Notice(
							"Could not open the program list",
							e.message);
						open_notice.add_response("ok", "OK");
						open_notice.present(this);
					}
				});
			});
		}
#endif

		/**
		 * Load installed Windows programs for ''agent_id''.
		 *
		 * @param agent_id selected machine agent id
		 */
		public void load(int agent_id)
		{
#if !ANDROID
			this.loaded_agent = agent_id;
#endif
			this.store.load(agent_id);
		}
	}
}
