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
	 * Machines that have one package name.
	 *
	 * A double-click or a long press on a Software grid opens this.
	 * The grid is {@link Argus.Controller.Store.PackageMachines}.
	 * Search filters by machine name or logged-in user. A green
	 * version is up to date. A red version has an update waiting.
	 * Hold the trash icon to uninstall that machine: Debian opens
	 * {@link AptDepends}, and Windows queues the uninstall command.
	 * Update available and Upgrade all sit at the bottom left when
	 * a red version is waiting. Each queues that script for every
	 * machine in that state. Cancel closes the dialog.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.PackageMachines(app, "deb");
	 * dialog.open(window, "bash");
	 * }}}
	 */
	public class PackageMachines : Adw.Dialog
	{
		public Argus.Controller.Application app;
		private Argus.Controller.Store.PackageMachines store;
		private Argus.Controller.Store.TaskTarget tasks;
		private Argus.Controller.Filters.PackageMachines filter;
		private Argus.Controller.Dialog.AptDepends depends;
		private Adw.ToastOverlay toasts;
		private string kind = "";
		private string package_name = "";
		private Gtk.ColumnViewColumn machines_column;
		private Gtk.SearchEntry search;
		private Gtk.Button update;
		private Gtk.Button upgrade;
		private Gtk.Label empty_label;
		private Gtk.Stack body;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }

		/**
		 * @param app the controller process
		 * @param kind ''deb'', ''rpm'', or ''programs''
		 */
		public PackageMachines(Argus.Controller.Application app, string kind)
		{
			Object(title: "Machines", content_width: 880, content_height: 520);
			this.app = app;
			this.kind = kind;
			this.store = new Argus.Controller.Store.PackageMachines(app);
			this.tasks = new Argus.Controller.Store.TaskTarget(app);
			this.depends = new Argus.Controller.Dialog.AptDepends(app);
			this.filter = new Argus.Controller.Filters.PackageMachines();
			var listed = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
			};
			var sorted = new Gtk.SortListModel(listed, null) {
				incremental = false
			};
			var grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = grid.sorter;
			var machines = new Gtk.SignalListItemFactory();
			machines.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			machines.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQV.PackageMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.machine;
				label.tooltip_text = row.machine;
			});
			var machine_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.PackageMachine), null, "machine");
			this.machines_column = new Gtk.ColumnViewColumn("Installed on these machines", machines) {
				expand = true,
				resizable = true,
				sorter = new Gtk.StringSorter(machine_expr) {
					ignore_case = true
				}
			};
			grid.append_column(this.machines_column);
			var users = new Gtk.SignalListItemFactory();
			users.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			users.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQV.PackageMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.logged_in_users;
				label.tooltip_text = row.logged_in_users;
			});
			var users_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.PackageMachine), null, "logged-in-users");
			grid.append_column(new Gtk.ColumnViewColumn("Logged in users", users) {
				fixed_width = 160,
				resizable = true,
				sorter = new Gtk.StringSorter(users_expr) {
					ignore_case = true
				}
			});
			var versions = new Gtk.SignalListItemFactory();
			versions.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					width_request = 180
				};
			});
			versions.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQV.PackageMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.version;
				label.remove_css_class("version-spread");
				label.remove_css_class("version-current");
				if (row.update_since > 0) {
					label.add_css_class("version-spread");
					label.tooltip_text = "Update available";
					return;
				}
				label.add_css_class("version-current");
				label.tooltip_text = "Up to date";
			});
			var version_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.PackageMachine), null, "version");
			grid.append_column(new Gtk.ColumnViewColumn("Version", versions) {
				fixed_width = 180,
				resizable = true,
				sorter = new Gtk.StringSorter(version_expr) {
					ignore_case = true
				}
			});
			if (this.kind == "deb" || this.kind == "programs") {
				var removes = new Gtk.SignalListItemFactory();
				removes.setup.connect((obj) => {
					var item = (Gtk.ListItem) obj;
					var hold = new Argus.Controller.Widget.HoldButton() {
						halign = Gtk.Align.CENTER,
						valign = Gtk.Align.CENTER,
						visible = false
					};
					hold.short_click.connect(() => {
						this.toasts.add_toast(new Adw.Toast("Click and hold to remove"));
					});
					hold.confirmed.connect(() => {
						if (item.item == null) {
							return;
						}
						var row = (Argus.Shared.SQV.PackageMachine) item.item;
						if (this.kind == "deb") {
							this.depends.open(this, this.package_name);
							return;
						}
						if (this.kind != "programs") {
							return;
						}
						var program = new Argus.Shared.OSQuery.Programs();
						program.name = this.package_name;
						program.uninstall_string = row.uninstall_string;
						if (program.silent_command() == "") {
							this.toasts.add_toast(new Adw.Toast(
								"No uninstall command found for " + this.package_name));
							return;
						}
						var ids = new Gee.ArrayList<int32>();
						ids.add((int32) row.agent_id);
						this.tasks.run_command(
							"Uninstall " + this.package_name, program.silent_command(), ids);
					});
					item.child = hold;
				});
				removes.bind.connect((obj) => {
					var item = (Gtk.ListItem) obj;
					var row = (Argus.Shared.SQV.PackageMachine) item.item;
					var hold = (Argus.Controller.Widget.HoldButton) item.child;
					hold.visible = this.kind == "deb" || row.uninstall_string.strip() != "";
					hold.tooltip_text = "Click and hold to remove";
				});
				grid.append_column(new Gtk.ColumnViewColumn("", removes) {
					fixed_width = 48,
					resizable = false
				});
			}
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search machines or users",
				hexpand = true
			};
			this.empty_label = new Gtk.Label("No machines") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				wrap = true
			};
			var wait = new Adw.Spinner() {
				width_request = 48,
				height_request = 48,
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE
			};
			this.body.add_named(wait, "wait");
			this.body.add_named(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true,
				min_content_height = 240
			}, "list");
			this.body.add_named(this.empty_label, "empty");
			var cancel = new Gtk.Button.with_label("Cancel");
			this.update = new Gtk.Button.with_label("Update available") {
				halign = Gtk.Align.START,
				visible = false
			};
			this.upgrade = new Gtk.Button.with_label("Upgrade all") {
				halign = Gtk.Align.START,
				visible = false
			};
			var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			actions.append(this.update);
			actions.append(this.upgrade);
			actions.append(new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				hexpand = true
			});
			actions.append(cancel);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			box.append(this.search);
			box.append(this.body);
			box.append(actions);
			this.toasts = new Adw.ToastOverlay() {
				child = box
			};
			this.child = this.toasts;
			cancel.clicked.connect(() => {
				this.close();
			});
			this.update.clicked.connect(() => {
				var ids = new Gee.ArrayList<int32>();
				foreach (var row in this.store.items) {
					if (row.update_since < 1) {
						continue;
					}
					ids.add((int32) row.agent_id);
				}
				if (this.kind == "deb") {
					this.tasks.run_script("linux", "apt", "update", ids);
					return;
				}
				if (this.kind == "rpm") {
					this.tasks.run_script("linux", "dnf", "update", ids);
				}
			});
			this.upgrade.clicked.connect(() => {
				var ids = new Gee.ArrayList<int32>();
				foreach (var row in this.store.items) {
					if (row.update_since < 1) {
						continue;
					}
					ids.add((int32) row.agent_id);
				}
				if (this.kind == "deb") {
					this.tasks.run_script("linux", "apt", "upgrade", ids);
					return;
				}
				if (this.kind == "rpm") {
					this.tasks.run_script("linux", "dnf", "upgrade", ids);
				}
			});
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
			});
			this.store.notify["busy"].connect(() => {
				if (this.store.busy) {
					this.update.visible = false;
					this.upgrade.visible = false;
					this.body.visible_child_name = "wait";
					return;
				}
				var any = false;
				if (this.kind == "deb" || this.kind == "rpm") {
					foreach (var row in this.store.items) {
						if (row.update_since > 0) {
							any = true;
							break;
						}
					}
				}
				this.update.visible = any;
				this.upgrade.visible = any;
				this.machines_column.title = "Installed on these machines";
				if (this.store.get_n_items() == 1) {
					this.machines_column.title = "Installed on this machine";
				}
				if (this.store.empty) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.store.failed.connect((heading, message) => {
				if (!this.showing) {
					return;
				}
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.tasks.failed.connect((heading, message) => {
				if (!this.showing) {
					return;
				}
				this.toasts.add_toast(new Adw.Toast(heading + ": " + message));
			});
			this.tasks.submitted.connect((count) => {
				if (!this.showing) {
					return;
				}
				var label = count == 1 ?
					"Task created and running — view it in the Tasks tab" :
					count.to_string() + " tasks created and running — view them in the Tasks tab";
				this.toasts.add_toast(new Adw.Toast(label));
			});
			this.closed.connect(() => {
				this.showing = false;
			});
		}

		/**
		 * Show the dialog and load machines for ''name''.
		 *
		 * @param parent window the dialog is attached to
		 * @param name package or program name
		 */
		public void open(Gtk.Widget parent, string name)
		{
			if (this.showing) {
				return;
			}
			this.package_name = name;
			this.title = name;
			this.search.text = "";
			this.filter.search = "";
			this.update.visible = false;
			this.upgrade.visible = false;
			this.showing = true;
			this.present(parent);
			this.store.load(name, this.kind);
		}
	}
}
