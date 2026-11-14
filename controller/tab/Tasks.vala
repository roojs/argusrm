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

namespace Argus.Controller.Tab
{
	/**
	 * Tasks page showing queued, running, and completed runs.
	 *
	 *  * The filter row writes {@link Argus.Controller.Filters.Tasks}.
	 *  * {@link Argus.Controller.Tab.Base.column_menu} builds the columns
	 *    from ''task_targets.csv''.
	 *  * Selecting a row opens the terminal log viewer in the bottom pane.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Tasks(window);
	 * stack.add_named(page, "tasks");
	 * }}}
	 */
	public class Tasks : Argus.Controller.Tab.Base
	{
		/**
		 * Controller window this page belongs to.
		 */
		public Argus.Controller.Window window;
		private GLib.ListStore store;
		private Argus.Controller.Filters.Tasks filter;

		/**
		 * Build the filter bar, task target grid, and terminal log pane.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Tasks(Argus.Controller.Window window)
		{
			Object(
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0,
				table: "task_targets",
				expand_column: "display-task"
			);
			this.window = window;
			this.hexpand = true;
			this.vexpand = true;
			this.store = new GLib.ListStore(typeof(Argus.Shared.SQT.TaskTarget));
			this.filter = new Argus.Controller.Filters.Tasks();
			var text_columns = new Gee.ArrayList<string>();
			var visible = new Gee.ArrayList<string>();
			foreach (var col in this.read_columns(this.table)) {
				if (col.format != "text") {
					continue;
				}
				text_columns.add(col.name);
				if (col.visible) {
					visible.add(col.name);
				}
			}
			this.filter.visible_text = visible;
			var rows = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			var group = this.column_grid(rows, false);
			group.action_state_changed.connect((action_name, state) => {
				if (!text_columns.contains(action_name)) {
					return;
				}
				var names = new Gee.ArrayList<string>();
				names.add_all(this.filter.visible_text);
				if (state.get_boolean()) {
					names.add(action_name);
				}
				if (!state.get_boolean()) {
					names.remove(action_name);
				}
				this.filter.visible_text = names;
			});
			var selection = (Gtk.SingleSelection) this.grid.model;
			selection.autoselect = false;
			selection.can_unselect = true;

			var search = new Gtk.SearchEntry() {
				placeholder_text = "Search machine or command",
				hexpand = true
			};
			search.search_changed.connect(() => {
				this.filter.search = search.text;
			});
			var state_names = new Gtk.StringList(null);
			state_names.append("Active");
			state_names.append("All");
			state_names.append("Completed");
			state_names.append("Failed");
			var state_drop = new Gtk.DropDown(
				state_names,
				new Gtk.PropertyExpression(typeof(Gtk.StringObject), null, "string"));
			state_drop.selected = 0;
			state_drop.notify["selected"].connect(() => {
				var label = state_names.get_string(state_drop.selected);
				if (label != null) {
					this.filter.state = label;
				}
			});

			var from_cal = new Gtk.Calendar();
			var to_cal = new Gtk.Calendar();
			var date_button = new Gtk.MenuButton() {
				label = "Date: Any"
			};
			var preset_any = new Gtk.Button.with_label("Any");
			var preset_today = new Gtk.Button.with_label("Today");
			var preset_week = new Gtk.Button.with_label("Last 7 days");
			var preset_month = new Gtk.Button.with_label("Last 30 days");
			var presets = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
			presets.append(preset_any);
			presets.append(preset_today);
			presets.append(preset_week);
			presets.append(preset_month);
			var cal_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			var from_col = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
			from_col.append(new Gtk.Label("From") { xalign = 0 });
			from_col.append(from_cal);
			var to_col = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
			to_col.append(new Gtk.Label("To") { xalign = 0 });
			to_col.append(to_cal);
			cal_box.append(from_col);
			cal_box.append(to_col);
			var apply_date = new Gtk.Button.with_label("Apply") {
				css_classes = { "suggested-action" },
				halign = Gtk.Align.END
			};
			var date_content = new Gtk.Box(Gtk.Orientation.VERTICAL, 10) {
				margin_top = 10,
				margin_bottom = 10,
				margin_start = 10,
				margin_end = 10
			};
			date_content.append(presets);
			date_content.append(cal_box);
			date_content.append(apply_date);
			var date_pop = new Gtk.Popover() {
				child = date_content
			};
			date_button.popover = date_pop;
			preset_any.clicked.connect(() => {
				this.filter.date_from = 0;
				this.filter.date_to = 0;
				date_button.label = "Date: Any";
				date_pop.popdown();
			});
			preset_today.clicked.connect(() => {
				var now = new GLib.DateTime.now_local();
				var start = new GLib.DateTime.local(
					now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
				this.filter.date_from = start.to_unix();
				this.filter.date_to = start.add_days(1).to_unix() - 1;
				date_button.label = "Date: Today";
				date_pop.popdown();
			});
			preset_week.clicked.connect(() => {
				var now = new GLib.DateTime.now_local();
				var start = new GLib.DateTime.local(
					now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
				this.filter.date_from = start.add_days(-6).to_unix();
				this.filter.date_to = start.add_days(1).to_unix() - 1;
				date_button.label = "Date: 7 days";
				date_pop.popdown();
			});
			preset_month.clicked.connect(() => {
				var now = new GLib.DateTime.now_local();
				var start = new GLib.DateTime.local(
					now.get_year(), now.get_month(), now.get_day_of_month(), 0, 0, 0);
				this.filter.date_from = start.add_days(-29).to_unix();
				this.filter.date_to = start.add_days(1).to_unix() - 1;
				date_button.label = "Date: 30 days";
				date_pop.popdown();
			});
			apply_date.clicked.connect(() => {
				var picked_from = from_cal.get_date();
				var picked_to = to_cal.get_date();
				var start = new GLib.DateTime.local(
					picked_from.get_year(), picked_from.get_month(),
					picked_from.get_day_of_month(), 0, 0, 0);
				var end = new GLib.DateTime.local(
					picked_to.get_year(), picked_to.get_month(),
					picked_to.get_day_of_month(), 23, 59, 59);
				if (end.to_unix() < start.to_unix()) {
					var swap = start;
					start = new GLib.DateTime.local(
						picked_to.get_year(), picked_to.get_month(),
						picked_to.get_day_of_month(), 0, 0, 0);
					end = new GLib.DateTime.local(
						swap.get_year(), swap.get_month(),
						swap.get_day_of_month(), 23, 59, 59);
				}
				this.filter.date_from = start.to_unix();
				this.filter.date_to = end.to_unix();
				var from_text = start.format("%Y-%m-%d");
				var to_text = end.format("%Y-%m-%d");
				date_button.label = (from_text != null ? from_text : "") +
					" - " + (to_text != null ? to_text : "");
				date_pop.popdown();
			});

			var refresh = new Gtk.Button() {
				icon_name = "view-refresh-symbolic",
				tooltip_text = "Refresh tasks"
			};
			var spinner = new Adw.Spinner() {
				visible = false
			};
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				css_classes = { "machines-filter" },
				hexpand = true
			};
			bar.append(search);
			bar.append(new Gtk.Label("State"));
			bar.append(state_drop);
			bar.append(date_button);
			bar.append(spinner);
			bar.append(refresh);

			var term_title = new Gtk.Label("") {
				xalign = 0,
				hexpand = true,
				ellipsize = Pango.EllipsizeMode.END
			};
			var term_meta = new Gtk.Label("") {
				css_classes = { "dim-label" }
			};
			var copy_button = new Gtk.Button() {
				icon_name = "edit-copy-symbolic",
				css_classes = { "flat" },
				tooltip_text = "Copy output"
			};
			var close_button = new Gtk.Button() {
				icon_name = "window-close-symbolic",
				css_classes = { "flat" },
				tooltip_text = "Close log view"
			};
			var term_header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				css_classes = { "tool-output-header" },
				hexpand = true
			};
			term_header.append(term_title);
			term_header.append(term_meta);
			term_header.append(copy_button);
			term_header.append(close_button);

			var term_view = new Gtk.TextView() {
				editable = false,
				cursor_visible = false,
				wrap_mode = Gtk.WrapMode.NONE,
				monospace = true,
				hexpand = true,
				vexpand = true,
				left_margin = 8,
				right_margin = 8,
				top_margin = 8,
				bottom_margin = 8,
				css_classes = { "tool-output" }
			};
			term_view.buffer.create_tag("stderr", "foreground", "#ff7b72", null);
			term_view.buffer.create_tag("stdin", "foreground", "#79c0ff", null);
			var term_scroll = new Gtk.ScrolledWindow() {
				child = term_view,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				hexpand = true,
				vexpand = true,
				css_classes = { "tool-output" }
			};
			var term_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				visible = false,
				hexpand = true,
				vexpand = true
			};
			term_box.append(term_header);
			term_box.append(term_scroll);

			copy_button.clicked.connect(() => {
				Gtk.TextIter start;
				Gtk.TextIter end;
				term_view.buffer.get_bounds(out start, out end);
				var content = term_view.buffer.get_text(start, end, false);
				if (content == "") {
					return;
				}
				var display = Gdk.Display.get_default();
				if (display != null) {
					display.get_clipboard().set_text(content);
				}
			});
			close_button.clicked.connect(() => {
				selection.unselect_all();
			});

			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = new Gtk.ScrolledWindow() {
					child = this.grid,
					hexpand = true,
					vexpand = true
				},
				end_child = term_box,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
			selection.selection_changed.connect((position, n_items) => {
				var row = selection.selected_item as Argus.Shared.SQT.TaskTarget;
				if (row == null) {
					term_box.visible = false;
					term_title.label = "";
					term_meta.label = "";
					term_view.buffer.text = "";
					return;
				}
				if (!term_box.visible) {
					term_box.visible = true;
					paned.position = paned.get_height() / 2;
				}
				var host = row.agent_id_hostname != "" ?
					row.agent_id_hostname : "Agent " + row.agent_id.to_string();
				term_title.label = host + " — " + row.display_task;
				var exit_text = row.display_exit != "" ? " · exit " + row.display_exit : "";
				term_meta.label = row.display_state + exit_text;
				term_view.buffer.text = "";
			});
			this.append(bar);
			this.append(paned);
		}
	}
}
