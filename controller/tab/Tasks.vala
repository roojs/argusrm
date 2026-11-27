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
		private Argus.Controller.Store.TaskTarget store;
		private Argus.Controller.Filters.Tasks filter;
		private int64 watched_id = 0;
		private int watched_identifier = 0;
		private int64 watched_ended = 0;
		private uint expiry_timer = 0;
		private bool stick_bottom = false;
		private bool auto_scrolling = false;
		private bool trimming = false;
		private uint trim_idle = 0;
		private uint scroll_idle = 0;

		/**
		 * Build the filter bar, task target grid, and terminal log pane.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Tasks(Argus.Controller.Window window)
		{
			base("task_targets", "display-task");
			this.window = window;
			this.store = new Argus.Controller.Store.TaskTarget(window.app);
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
#if ANDROID
			cal_box.orientation = Gtk.Orientation.VERTICAL;
#endif
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
			var bar_spinner = new Adw.Spinner() {
				visible = false
			};
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
			bar.append(new Gtk.Label("State"));
			bar.append(state_drop);
			bar.append(date_button);
			bar.append(bar_spinner);
			bar.append(refresh);
#else
			bar.append(search);
			bar.append(new Gtk.Label("State"));
			bar.append(state_drop);
			bar.append(date_button);
			bar.append(bar_spinner);
			bar.append(refresh);
#endif

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
			term_view.buffer.create_tag("status-ok", "foreground", "#3fb950", null);
			var term_scroll = new Gtk.ScrolledWindow() {
				child = term_view,
				hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
				hexpand = true,
				vexpand = true,
				css_classes = { "tool-output" }
			};
			term_view.buffer.changed.connect(() => {
				if (this.trimming) {
					return;
				}
				this.stick_bottom = true;
				if (this.trim_idle == 0) {
					this.trim_idle = GLib.Idle.add(() => {
						this.trim_idle = 0;
						Gtk.TextIter buf_end;
						term_view.buffer.get_end_iter(out buf_end);
						var line_count = term_view.buffer.get_line_count();
						if (buf_end.get_line_offset() == 0 && line_count > 1) {
							line_count--;
						}
						if (line_count > 200) {
							Gtk.TextIter buf_start;
							Gtk.TextIter cut;
							term_view.buffer.get_start_iter(out buf_start);
							term_view.buffer.get_iter_at_line(out cut, line_count - 200);
							this.trimming = true;
							term_view.buffer.delete(ref buf_start, ref cut);
							this.trimming = false;
						}
						return false;
					}, GLib.Priority.HIGH);
				}
				if (this.scroll_idle == 0) {
					this.scroll_idle = GLib.Idle.add(() => {
						this.scroll_idle = 0;
						if (!this.stick_bottom) {
							return false;
						}
						var target = term_scroll.vadjustment.upper -
							term_scroll.vadjustment.page_size;
						if (target < term_scroll.vadjustment.lower) {
							target = term_scroll.vadjustment.lower;
						}
						this.auto_scrolling = true;
						term_scroll.vadjustment.value = target;
						this.auto_scrolling = false;
						return false;
					});
				}
			});
			term_scroll.vadjustment.changed.connect(() => {
				if (!this.stick_bottom || this.scroll_idle != 0) {
					return;
				}
				this.scroll_idle = GLib.Idle.add(() => {
					this.scroll_idle = 0;
					if (!this.stick_bottom) {
						return false;
					}
					var target = term_scroll.vadjustment.upper -
						term_scroll.vadjustment.page_size;
					if (target < term_scroll.vadjustment.lower) {
						target = term_scroll.vadjustment.lower;
					}
					this.auto_scrolling = true;
					term_scroll.vadjustment.value = target;
					this.auto_scrolling = false;
					return false;
				});
			});
			term_scroll.vadjustment.value_changed.connect(() => {
				if (this.auto_scrolling || this.scroll_idle != 0) {
					return;
				}
				this.stick_bottom = term_scroll.vadjustment.value >=
					term_scroll.vadjustment.upper - term_scroll.vadjustment.page_size - 1.0;
			});
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

#if ANDROID
			var paned = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
				hexpand = true,
				vexpand = true
			};
			var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL) {
				visible = false
			};
			paned.append(this.overlay);
			paned.append(sep);
			paned.append(term_box);
#else
			var paned = new Gtk.Paned(Gtk.Orientation.VERTICAL) {
				start_child = this.overlay,
				end_child = term_box,
				resize_start_child = true,
				resize_end_child = true,
				hexpand = true,
				vexpand = true
			};
#endif
			this.store.bind_property("busy", bar_spinner, "visible", GLib.BindingFlags.SYNC_CREATE);
			refresh.clicked.connect(() => {
				this.store.load();
			});
			this.store.failed.connect((heading, message) => {
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			this.store.logs_loaded.connect((target_id, stdout_text, stderr_text, stdin_text) => {
				if ((int64) target_id != this.watched_id) {
					return;
				}
				term_view.buffer.text = "";
				Gtk.TextIter end;
				if (stdin_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(ref end, stdin_text, -1, "stdin");
				}
				if (stdout_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert(ref end, stdout_text, -1);
				}
				if (stderr_text != "") {
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(ref end, stderr_text, -1, "stderr");
				}
				foreach (var item in this.store.items) {
					if (item.id != this.watched_id || (item.ended == 0 && !item.is_cancelled)) {
						continue;
					}
					var prefix = "";
					if (term_view.buffer.get_char_count() > 0) {
						term_view.buffer.get_end_iter(out end);
						var tail = end;
						tail.backward_char();
						prefix = tail.get_char() == '\n' ? "\n" : "\n\n";
					}
					if (item.is_cancelled) {
						term_view.buffer.get_end_iter(out end);
						term_view.buffer.insert_with_tags_by_name(
							ref end, prefix + "Command cancelled\n", -1, "stderr");
						break;
					}
					if (item.success == 0) {
						term_view.buffer.get_end_iter(out end);
						term_view.buffer.insert_with_tags_by_name(
							ref end, prefix + "Command succeeded (exit 0)\n", -1, "status-ok");
						break;
					}
					term_view.buffer.get_end_iter(out end);
					term_view.buffer.insert_with_tags_by_name(
						ref end,
						prefix + "Command failed (exit " + item.success.to_string() + ")\n",
						-1, "stderr");
					break;
				}
			});
			this.store.items_changed.connect((position, removed, added) => {
				if (this.watched_id < 1) {
					return;
				}
				foreach (var item in this.store.items) {
					if (item.id != this.watched_id) {
						continue;
					}
					this.watched_identifier = item.identifier;
					var exit_text = item.display_exit != "" ? " · exit " + item.display_exit : "";
					term_meta.label = item.display_state + exit_text;
					if (item.ended > 0 && this.watched_ended == 0) {
						this.watched_ended = item.ended;
						this.store.fetch_logs((int) this.watched_id);
					}
					break;
				}
				var total = selection.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var shown = selection.get_item(i) as Argus.Shared.SQT.TaskTarget;
					if (shown == null || shown.id != this.watched_id) {
						continue;
					}
					selection.select_item(i, true);
					break;
				}
			});
			selection.selection_changed.connect((position, n_items) => {
				if (this.store.busy) {
					return;
				}
				var row = selection.selected_item as Argus.Shared.SQT.TaskTarget;
				if (row == null) {
					this.watched_id = 0;
					this.watched_identifier = 0;
					this.watched_ended = 0;
					term_box.visible = false;
#if ANDROID
					sep.visible = false;
					this.overlay.height_request = -1;
					this.overlay.vexpand = true;
#endif
					term_title.label = "";
					term_meta.label = "";
					term_view.buffer.text = "";
					return;
				}
				if (row.id == this.watched_id) {
					return;
				}
				this.watched_id = row.id;
				this.watched_identifier = row.identifier;
				this.watched_ended = row.ended;
				if (!term_box.visible) {
					term_box.visible = true;
#if ANDROID
					sep.visible = true;
					this.overlay.vexpand = false;
					this.overlay.height_request = 200;
#else
					paned.position = paned.get_height() / 2;
#endif
				}
				var host = row.agent_id_hostname != "" ?
					row.agent_id_hostname : "Agent " + row.agent_id.to_string();
				term_title.label = host + " — " + row.display_task;
				var exit_text = row.display_exit != "" ? " · exit " + row.display_exit : "";
				term_meta.label = row.display_state + exit_text;
				term_view.buffer.text = "";
				this.store.fetch_logs((int) row.id);
				if (row.ended == 0 && !row.is_cancelled) {
					this.store.watch((int) row.id);
				}
			});
			this.window.app.rpc.notification.connect((notification) => {
				switch (notification.method) {
					case "event.task":
					case "event.agent":
						this.store.load();
						break;

					case "controller.stdin":
						if (this.watched_identifier < 1 || notification.args.size < 2 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						var command_text = notification.args.get(1).get_string();
						if (command_text == "") {
							break;
						}
						Gtk.TextIter in_start;
						Gtk.TextIter in_end;
						term_view.buffer.get_bounds(out in_start, out in_end);
						if (term_view.buffer.get_text(in_start, in_end, false).has_prefix(command_text)) {
							break;
						}
						term_view.buffer.get_start_iter(out in_start);
						term_view.buffer.insert_with_tags_by_name(
							ref in_start, command_text, -1, "stdin");
						break;

					case "controller.stdout":
						if (this.watched_identifier < 1 || notification.args.size < 2 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						Gtk.TextIter out_end;
						term_view.buffer.get_end_iter(out out_end);
						term_view.buffer.insert(
							ref out_end, notification.args.get(1).get_string(), -1);
						break;

					case "controller.stderr":
						if (this.watched_identifier < 1 || notification.args.size < 2 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						Gtk.TextIter err_end;
						term_view.buffer.get_end_iter(out err_end);
						term_view.buffer.insert_with_tags_by_name(
							ref err_end, notification.args.get(1).get_string(), -1, "stderr");
						break;

					case "controller.ended":
						if (this.watched_identifier < 1 || notification.args.size < 1 ||
							notification.args.get(0).get_int() != this.watched_identifier) {
							break;
						}
						this.store.load();
						break;

					default:
						break;
				}
			});
			this.map.connect(() => {
				this.store.load();
				if (this.expiry_timer == 0) {
					this.expiry_timer = GLib.Timeout.add_seconds(60, () => {
						this.filter.changed(Gtk.FilterChange.DIFFERENT);
						return true;
					});
				}
			});
			this.unmap.connect(() => {
				if (this.expiry_timer != 0) {
					GLib.Source.remove(this.expiry_timer);
					this.expiry_timer = 0;
				}
			});
			this.content.append(bar);
#if ANDROID
			this.content.append(search_bar);
#endif
			this.content.append(paned);
		}
	}
}
