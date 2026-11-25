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

namespace Argus.Controller.Tab.Asset
{
	/**
	 * Windows program grid on the Software page.
	 *
	 * {@link Argus.Controller.Tab.Base.column_menu} reads
	 * ''programs.csv''. {@link Argus.Controller.Store.Programs}
	 * loads ''Programs.list'' with zero, every agent.
	 * {@link Argus.Controller.Filters.Programs} is the bar above
	 * the grid: search, Filters, and versions differ.
	 * A double-click, or a long press, opens
	 * {@link Argus.Controller.Dialog.PackageMachines} for that name.
	 * Several rows can be selected. A right-click on a row opens
	 * Categorize. The choice is stored by ''ProgramClass.classify''.
	 * The grid loads when this page is shown. An empty grid
	 * shows a spinner over it while that call is in flight.
	 * {@link refreshing} is true when rows are already shown
	 * and a later call is in flight.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.Programs(window);
	 * }}}
	 */
	public class Programs : Argus.Controller.Tab.Base
	{
		public Argus.Controller.Window window;
		private Argus.Controller.Store.Programs store;
		private Argus.Controller.Filters.Programs filter;
		private Argus.Controller.Dialog.PackageMachines machines;

		/**
		 * Build the grid.
		 *
		 * @param window the window this page belongs to
		 */
		public Programs(Argus.Controller.Window window)
		{
			base("programs", "name");
			this.window = window;
			this.store = new Argus.Controller.Store.Programs(window.app);
			this.filter = new Argus.Controller.Filters.Programs();
			this.machines = new Argus.Controller.Dialog.PackageMachines(window.app, "programs");
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			this.column_grid(rows, true);
			var rate_group = new GLib.SimpleActionGroup();
			var rate = new GLib.SimpleAction("classify", GLib.VariantType.INT32);
			rate.activate.connect((parameter) => {
				if (parameter == null) {
					return;
				}
				var rating = parameter.get_int32();
				var selection = (Gtk.MultiSelection) this.grid.model;
				var chosen = selection.get_selection();
				string[] refs = {};
				uint index = 0;
				while (index < chosen.get_size()) {
					var at = chosen.get_nth(index);
					var row = (Argus.Shared.OSQuery.Programs) selection.get_item(at);
					refs += row.source + "\n" + row.name;
					index++;
				}
				if (refs.length == 0) {
					return;
				}
				this.window.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "ProgramClass.classify",
					args = OLLMrpc.args("iS", rating, refs, refs.length)
				}, (obj, res) => {
					OLLMrpc.Response response;
					try {
						response = this.window.app.rpc.call.end(res);
					} catch (GLib.Error e) {
						this.toasts.add_toast(new Adw.Toast(e.message));
						return;
					}
					if (response.error != null) {
						this.toasts.add_toast(new Adw.Toast(response.error.message));
						return;
					}
					this.store.load(0);
				});
			});
			rate_group.add_action(rate);
			this.insert_action_group("software", rate_group);
			var system_mark = new Gtk.Image() {
				pixel_size = 16
			};
			Argus.Shared.OSQuery.ProgramClass.Rating.SYSTEM.show(system_mark);
			var system_text = new Gtk.Label("System - included with Windows") {
				xalign = 0,
				hexpand = true
			};
			var system_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			system_row.append(system_mark);
			system_row.append(system_text);
			var system_button = new Gtk.Button() {
				child = system_row,
				has_frame = false,
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			var keep_mark = new Gtk.Image() {
				pixel_size = 16
			};
			Argus.Shared.OSQuery.ProgramClass.Rating.INSTALLED.show(keep_mark);
			var keep_text = new Gtk.Label("Keep - regular application") {
				xalign = 0,
				hexpand = true
			};
			var keep_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			keep_row.append(keep_mark);
			keep_row.append(keep_text);
			var keep_button = new Gtk.Button() {
				child = keep_row,
				has_frame = false,
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			var bad_mark = new Gtk.Image() {
				pixel_size = 16
			};
			Argus.Shared.OSQuery.ProgramClass.Rating.BAD.show(bad_mark);
			var bad_text = new Gtk.Label("Bad - this should probably be removed") {
				xalign = 0,
				hexpand = true
			};
			var bad_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			bad_row.append(bad_mark);
			bad_row.append(bad_text);
			var bad_button = new Gtk.Button() {
				child = bad_row,
				has_frame = false,
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			var unknown_mark = new Gtk.Image() {
				pixel_size = 16
			};
			Argus.Shared.OSQuery.ProgramClass.Rating.UNKNOWN.show(unknown_mark);
			var unknown_text = new Gtk.Label("Unknown - need to check") {
				xalign = 0,
				hexpand = true
			};
			var unknown_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			unknown_row.append(unknown_mark);
			unknown_row.append(unknown_text);
			var unknown_button = new Gtk.Button() {
				child = unknown_row,
				has_frame = false,
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			var choice_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			choice_list.append(system_button);
			choice_list.append(keep_button);
			choice_list.append(bad_button);
			choice_list.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
			choice_list.append(unknown_button);
			var choices = new Gtk.Popover() {
				has_arrow = false,
				position = Gtk.PositionType.RIGHT,
				autohide = true,
				child = choice_list
			};
			var categorize_text = new Gtk.Label("Categorize") {
				xalign = 0,
				hexpand = true
			};
			var categorize_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
			categorize_row.append(categorize_text);
			categorize_row.append(new Gtk.Image.from_icon_name("go-next-symbolic"));
			var categorize_button = new Gtk.Button() {
				child = categorize_row,
				has_frame = false,
				hexpand = true,
				halign = Gtk.Align.FILL
			};
			choices.set_parent(categorize_button);
			categorize_button.clicked.connect(() => {
				choices.popup();
			});
			var rate_menu = new Gtk.Popover() {
				has_arrow = false,
				position = Gtk.PositionType.BOTTOM,
				autohide = true,
				cascade_popdown = true,
				child = categorize_button
			};
			rate_menu.set_parent(this.grid);
			system_button.clicked.connect(() => {
				rate.activate(new GLib.Variant.int32(
					Argus.Shared.OSQuery.ProgramClass.Rating.SYSTEM));
				rate_menu.popdown();
			});
			keep_button.clicked.connect(() => {
				rate.activate(new GLib.Variant.int32(
					Argus.Shared.OSQuery.ProgramClass.Rating.INSTALLED));
				rate_menu.popdown();
			});
			bad_button.clicked.connect(() => {
				rate.activate(new GLib.Variant.int32(
					Argus.Shared.OSQuery.ProgramClass.Rating.BAD));
				rate_menu.popdown();
			});
			unknown_button.clicked.connect(() => {
				rate.activate(new GLib.Variant.int32(
					Argus.Shared.OSQuery.ProgramClass.Rating.UNKNOWN));
				rate_menu.popdown();
			});
			var menu_click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_SECONDARY,
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			var menu_press = false;
			menu_click.pressed.connect((n_press, x, y) => {
				menu_press = false;
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					menu_click.set_state(Gtk.EventSequenceState.DENIED);
					return;
				}
				menu_click.set_state(Gtk.EventSequenceState.CLAIMED);
				menu_press = true;
				var selection = (Gtk.MultiSelection) this.grid.model;
				if (!selection.is_selected(row_item.position)) {
					selection.select_item(row_item.position, true);
				}
			});
			menu_click.released.connect((n_press, x, y) => {
				if (!menu_press) {
					return;
				}
				menu_press = false;
				rate_menu.set_pointing_to(Gdk.Rectangle() {
					x = (int) x,
					y = (int) y,
					width = 1,
					height = 1
				});
				rate_menu.popup();
			});
			this.grid.add_controller(menu_click);
			this.store.failed.connect((heading, message) => {
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.map.connect(() => {
				this.store.load(0);
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
				if (row == null) {
					return;
				}
				this.store.load_machines(row.name, row.source);
			});
			this.store.machines_loaded.connect((name, rows) => {
				var grouped = new Gee.HashMap<string, Gee.ArrayList<int32>>();
				var total = 0;
				foreach (var row in rows) {
					if (row.agent_id < 1) {
						continue;
					}
					var cmd = row.silent_command();
					if (cmd == "") {
						continue;
					}
					if (!grouped.has_key(cmd)) {
						grouped.set(cmd, new Gee.ArrayList<int32>());
					}
					var ids = grouped.get(cmd);
					if (!ids.contains((int32) row.agent_id)) {
						ids.add((int32) row.agent_id);
						total++;
					}
				}
				if (total < 1) {
					this.toasts.add_toast(new Adw.Toast(
						"No uninstall command found for " + name));
					return;
				}
				var count_label = total == 1 ? "1 machine" : total.to_string() + " machines";
				this.on_delete_all("Uninstall " + name,
						"This removes " + name + " from " + count_label + ".\nType \"delete all\" to confirm.",
						grouped, name);
			});
			this.delete_all.connect((commands, software) => {
				foreach (var entry_cmd in commands.entries) {
					task_store.run_command(
						"Uninstall " + software, entry_cmd.key, entry_cmd.value);
				}
			});
			var filters = this.filter.menu();
			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var spread = new Gtk.CheckButton.with_label("Versions differ");
			spread.toggled.connect(() => {
				this.filter.spread = spread.active;
			});
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
#if ANDROID
			bar.spacing = 6;
			var search_toggle = new Gtk.ToggleButton() {
				icon_name = "system-search-symbolic",
				tooltip_text = "Search"
			};
			var search_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				css_classes = { "machines-filter" },
				hexpand = true,
				visible = false
			};
			search_bar.append(search);
			search_toggle.toggled.connect(() => {
				search_bar.visible = search_toggle.active;
				if (search_toggle.active) {
					search.grab_focus();
				}
			});
			bar.append(search_toggle);
			bar.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			bar.append(filters);
			bar.append(spread);
			this.content.append(bar);
			this.content.append(search_bar);
#else
			bar.append(search);
			bar.append(filters);
			bar.append(spread);
			this.content.append(bar);
#endif
			var click = new Gtk.GestureClick() {
				button = Gdk.BUTTON_PRIMARY
			};
			click.pressed.connect((n_press, x, y) => {
				if (n_press < 2) {
					return;
				}
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window,
					((Argus.Shared.OSQuery.Programs) row_item.item).name);
			});
			var hold = new Gtk.GestureLongPress() {
				touch_only = true
			};
			hold.pressed.connect((x, y) => {
				var row_item = this.pick(x, y);
				if (row_item == null || row_item.item == null) {
					return;
				}
				this.machines.open(this.window,
					((Argus.Shared.OSQuery.Programs) row_item.item).name);
			});
			this.grid.add_controller(click);
			this.grid.add_controller(hold);
			this.content.append(this.overlay);
		}

		/**
		 * The words ''delete all'' were confirmed for one uninstall.
		 *
		 * @param commands one command and the agents that run it
		 * @param name software name
		 */
		private signal void delete_all(
			Gee.HashMap<string, Gee.ArrayList<int32>> commands,
			string name);

		/**
		 * Ask for the words ''delete all''.
		 *
		 * Uninstall stays off until the entry matches those words.
		 * A match emits {@link delete_all}.
		 *
		 * @param heading dialog title
		 * @param body dialog text
		 * @param commands one command and the agents that run it
		 * @param name software name
		 */
		private void on_delete_all(
			string heading,
			string body,
			Gee.HashMap<string, Gee.ArrayList<int32>> commands,
			string name)
		{
			var confirm = new Adw.AlertDialog(heading, body);
			var entry = new Gtk.Entry() {
				placeholder_text = "delete all"
			};
			confirm.set_extra_child(entry);
			confirm.add_response("cancel", "Cancel");
			confirm.add_response("uninstall", "Uninstall");
			confirm.set_response_appearance(
				"uninstall", Adw.ResponseAppearance.DESTRUCTIVE);
			confirm.set_response_enabled("uninstall", false);
			confirm.set_default_response("cancel");
			confirm.set_close_response("cancel");
			entry.changed.connect(() => {
				confirm.set_response_enabled(
					"uninstall", entry.text.strip() == "delete all");
			});
			confirm.response.connect((response) => {
				if (response != "uninstall" || entry.text.strip() != "delete all") {
					return;
				}
				this.delete_all(commands, name);
			});
			confirm.present(this);
		}
	}
}
