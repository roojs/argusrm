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
	 * One machine on the update upgrade dialog.
	 *
	 * Not a table and not a wire type. The dialog copies these from
	 * the Machines list. {@link kind} is ''deb'' or ''rpm''.
	 * {@link picked} is the tick on that row. {@link needs_upgrade}
	 * is true when that machine already has a package update waiting.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var row = new Argus.Controller.Dialog.UpgradeTarget() {
	 *     machine = "office",
	 *     kind = "deb",
	 *     picked = true
	 * };
	 * }}}
	 */
	public class UpgradeTarget : GLib.Object
	{
		/**
		 * ''agent.id'' of this machine.
		 */
		public int64 agent_id { get; set; default = 0; }
		/**
		 * Name shown in the grid.
		 */
		public string machine { get; set; default = ""; }
		/**
		 * Distinct logged-in users, comma separated, or empty.
		 */
		public string logged_in_users { get; set; default = ""; }
		/**
		 * Platform tab. ''deb'' or ''rpm''.
		 */
		public string kind { get; set; default = ""; }
		/**
		 * True when the tick on this row is on.
		 */
		public bool picked { get; set; default = false; }
		/**
		 * True when this machine has a package update waiting.
		 */
		public bool needs_upgrade { get; set; default = false; }
	}

	/**
	 * Update or upgrade Debian and RPM machines.
	 *
	 * The up arrow on the Machines filter bar opens this. The title
	 * is Update Upgrade. Debian packages and RPM packages share one
	 * full-width switcher, with the same icons as the Software page.
	 * The list is every machine of that platform. Search filters the
	 * current tab. Select all ticks the machines currently listed,
	 * and the same button becomes Select none once they are all
	 * ticked. Update selected queues the update script for the ticked
	 * machines. Upgrade selected queues the upgrade script for the
	 * ticked machines that already have an update waiting, and stays
	 * hidden when the current tab has none. Close dismisses the dialog.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.Upgrade(app);
	 * dialog.open(window, machines);
	 * }}}
	 */
	public class Upgrade : Adw.Dialog
	{
		public Argus.Controller.Application app;
		private GLib.ListStore rows;
		private Argus.Controller.Filters.Upgrade filter;
		private Argus.Controller.Store.TaskTarget tasks;
		private Gtk.FilterListModel listed;
		private Gtk.SearchEntry search;
		private Gtk.Button select;
		private Adw.ToggleGroup platforms;
		private Gtk.Button update;
		private Gtk.Button upgrade;
		private Gtk.Label empty_label;
		private Gtk.Stack body;
		private Adw.ToastOverlay toasts;
		private bool filling = false;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }

		/**
		 * @param app the controller process
		 */
		public Upgrade(Argus.Controller.Application app)
		{
			Object(title: "Update Upgrade", content_width: 880, content_height: 520);
			this.app = app;
			this.rows = new GLib.ListStore(typeof(Argus.Controller.Dialog.UpgradeTarget));
			this.filter = new Argus.Controller.Filters.Upgrade();
			this.tasks = new Argus.Controller.Store.TaskTarget(app);
			this.listed = new Gtk.FilterListModel(this.rows, this.filter) {
				incremental = false
			};
			var sorted = new Gtk.SortListModel(this.listed, null) {
				incremental = false
			};
			var grid = new Gtk.ColumnView(new Gtk.SingleSelection(sorted)) {
				hexpand = true,
				vexpand = true,
				show_row_separators = true
			};
			sorted.sorter = grid.sorter;
			var checks = new Gtk.SignalListItemFactory();
			checks.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.CheckButton() {
					halign = Gtk.Align.CENTER,
					valign = Gtk.Align.CENTER
				};
			});
			checks.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Controller.Dialog.UpgradeTarget) item.item;
				var check = (Gtk.CheckButton) item.child;
				check.set_data("argus-column-binding", row.bind_property(
					"picked", check, "active",
					GLib.BindingFlags.BIDIRECTIONAL | GLib.BindingFlags.SYNC_CREATE));
			});
			checks.unbind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				if (item.child == null) {
					return;
				}
				var binding = item.child.get_data<GLib.Binding>("argus-column-binding");
				if (binding != null) {
					binding.unbind();
				}
				item.child.set_data<GLib.Binding>("argus-column-binding", null);
			});
			grid.append_column(new Gtk.ColumnViewColumn("", checks) {
				fixed_width = 48,
				resizable = false
			});
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
				var row = (Argus.Controller.Dialog.UpgradeTarget) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.machine;
				label.tooltip_text = row.machine;
			});
			var machine_expr = new Gtk.PropertyExpression(
				typeof(Argus.Controller.Dialog.UpgradeTarget), null, "machine");
			grid.append_column(new Gtk.ColumnViewColumn("Machine", machines) {
				expand = true,
				resizable = true,
				sorter = new Gtk.StringSorter(machine_expr) {
					ignore_case = true
				}
			});
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
				var row = (Argus.Controller.Dialog.UpgradeTarget) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.logged_in_users;
				label.tooltip_text = row.logged_in_users;
			});
			var users_expr = new Gtk.PropertyExpression(
				typeof(Argus.Controller.Dialog.UpgradeTarget), null, "logged-in-users");
			grid.append_column(new Gtk.ColumnViewColumn("Logged in users", users) {
				fixed_width = 160,
				resizable = true,
				sorter = new Gtk.StringSorter(users_expr) {
					ignore_case = true
				}
			});
			this.platforms = new Adw.ToggleGroup() {
				orientation = Gtk.Orientation.HORIZONTAL,
				homogeneous = true,
				hexpand = true
			};
			this.platforms.add_css_class("both");
			var debian_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			debian_row.append(new Gtk.Image.from_icon_name("emblem-debian-symbolic"));
			debian_row.append(new Gtk.Label("Debian packages"));
			this.platforms.add(new Adw.Toggle() {
				name = "deb",
				child = new Gtk.CenterBox() {
					center_widget = debian_row,
					hexpand = true
				}
			});
			var rpm_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			rpm_row.append(new Gtk.Image.from_icon_name("application-x-rpm-symbolic"));
			rpm_row.append(new Gtk.Label("RPM packages"));
			this.platforms.add(new Adw.Toggle() {
				name = "rpm",
				child = new Gtk.CenterBox() {
					center_widget = rpm_row,
					hexpand = true
				}
			});
			var tabs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 12,
				margin_bottom = 4
			};
			tabs.append(this.platforms);
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search machines or users",
				hexpand = true
			};
			this.select = new Gtk.Button.with_label("Select all") {
				halign = Gtk.Align.END
			};
			this.empty_label = new Gtk.Label("No Debian machines") {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER,
				wrap = true
			};
			this.body = new Gtk.Stack() {
				hexpand = true,
				vexpand = true,
				transition_type = Gtk.StackTransitionType.NONE,
				margin_start = 16,
				margin_end = 16
			};
			this.body.add_named(new Gtk.ScrolledWindow() {
				child = grid,
				hexpand = true,
				vexpand = true,
				min_content_height = 240
			}, "list");
			this.body.add_named(this.empty_label, "empty");
			this.body.visible_child_name = "empty";
			var close = new Gtk.Button.with_label("Close");
			this.update = new Gtk.Button.with_label("Update selected") {
				sensitive = false
			};
			this.upgrade = new Gtk.Button.with_label("Upgrade selected") {
				css_classes = { "suggested-action" },
				sensitive = false,
				visible = false
			};
			var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END,
				margin_start = 16,
				margin_end = 16,
				margin_bottom = 16
			};
			actions.append(this.update);
			actions.append(this.upgrade);
			actions.append(close);
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				margin_start = 16,
				margin_end = 16
			};
			bar.append(this.search);
			bar.append(this.select);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
			box.append(tabs);
			box.append(bar);
			box.append(this.body);
			box.append(actions);
			this.toasts = new Adw.ToastOverlay() {
				child = box
			};
			this.child = this.toasts;
			close.clicked.connect(() => {
				this.close();
			});
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
			});
			this.select.clicked.connect(() => {
				var total = this.listed.get_n_items();
				var all = total > 0;
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.listed.get_item(i);
					if (!row.picked) {
						all = false;
						break;
					}
				}
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.listed.get_item(i);
					row.picked = !all;
				}
			});
			this.platforms.notify["active-name"].connect(() => {
				if (this.filling) {
					return;
				}
				var name = this.platforms.active_name;
				if (name == null || name == "") {
					return;
				}
				this.filter.kind = name;
			});
			this.listed.items_changed.connect((position, removed, added) => {
				if (this.filter.search.strip() != "") {
					this.empty_label.label = "No machines";
				} else if (this.filter.kind == "rpm") {
					this.empty_label.label = "No RPM machines";
				} else {
					this.empty_label.label = "No Debian machines";
				}
				var listed_total = this.listed.get_n_items();
				var all = listed_total > 0;
				for (var i = (uint) 0; i < listed_total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.listed.get_item(i);
					if (!row.picked) {
						all = false;
						break;
					}
				}
				if (all) {
					this.select.label = "Select none";
				} else {
					this.select.label = "Select all";
				}
				if (listed_total < 1) {
					this.body.visible_child_name = "empty";
					return;
				}
				this.body.visible_child_name = "list";
			});
			this.filter.notify["kind"].connect(() => {
				var picked_any = false;
				var upgrade_any = false;
				var upgrade_picked = false;
				var total = this.rows.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.rows.get_item(i);
					if (row.kind != this.filter.kind) {
						continue;
					}
					if (row.needs_upgrade) {
						upgrade_any = true;
					}
					if (!row.picked) {
						continue;
					}
					picked_any = true;
					if (row.needs_upgrade) {
						upgrade_picked = true;
					}
				}
				this.update.sensitive = picked_any;
				this.upgrade.visible = upgrade_any;
				this.upgrade.sensitive = upgrade_picked;
			});
			this.update.clicked.connect(() => {
				var ids = new Gee.ArrayList<int32>();
				var total = this.rows.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.rows.get_item(i);
					if (!row.picked || row.kind != this.filter.kind) {
						continue;
					}
					ids.add((int32) row.agent_id);
					row.picked = false;
				}
				if (this.filter.kind == "deb") {
					this.tasks.run_script("linux", "apt", "update", ids);
					return;
				}
				if (this.filter.kind == "rpm") {
					this.tasks.run_script("linux", "dnf", "update", ids);
				}
			});
			this.upgrade.clicked.connect(() => {
				var ids = new Gee.ArrayList<int32>();
				var total = this.rows.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.rows.get_item(i);
					if (!row.picked || !row.needs_upgrade || row.kind != this.filter.kind) {
						continue;
					}
					ids.add((int32) row.agent_id);
					row.picked = false;
				}
				if (this.filter.kind == "deb") {
					this.tasks.run_script("linux", "apt", "upgrade", ids);
					return;
				}
				if (this.filter.kind == "rpm") {
					this.tasks.run_script("linux", "dnf", "upgrade", ids);
				}
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
		 * Show every Debian and RPM machine from ''machines''.
		 *
		 * @param parent window the dialog is attached to
		 * @param machines rows already loaded on the Machines list
		 */
		public void open(
			Gtk.Widget parent,
			Gee.ArrayList<Argus.Shared.OSQuery.SystemInfo> machines
		) {
			if (this.showing) {
				return;
			}
			this.rows.remove_all();
			var deb_count = 0;
			var rpm_count = 0;
			var upgrade_count = 0;
			foreach (var machine in machines) {
				if (machine.agent_id < 1) {
					continue;
				}
				var kind = "";
				var pm = machine.package_manager();
				if (pm == Argus.Shared.OSQuery.PackageManager.APT) {
					kind = "deb";
					deb_count++;
				} else if (pm == Argus.Shared.OSQuery.PackageManager.DNF) {
					kind = "rpm";
					rpm_count++;
				}
				if (kind == "") {
					continue;
				}
				var target = new Argus.Controller.Dialog.UpgradeTarget();
				target.agent_id = machine.agent_id;
				target.kind = kind;
				target.needs_upgrade = machine.pkgs_status == 0;
				target.logged_in_users = machine.logged_in_users;
				target.machine = machine.hostname.strip();
				if (target.machine == "") {
					target.machine = machine.computer_name.strip();
				}
				if (target.machine == "") {
					target.machine = machine.local_hostname.strip();
				}
				if (target.machine == "") {
					target.machine = machine.agent_id.to_string();
				}
				if (target.needs_upgrade && kind == "deb") {
					upgrade_count++;
				}
				target.notify["picked"].connect(() => {
					var picked_any = false;
					var upgrade_any = false;
					var upgrade_picked = false;
					var total = this.rows.get_n_items();
					for (var i = (uint) 0; i < total; i++) {
						var row = (Argus.Controller.Dialog.UpgradeTarget) this.rows.get_item(i);
						if (row.kind != this.filter.kind) {
							continue;
						}
						if (row.needs_upgrade) {
							upgrade_any = true;
						}
						if (!row.picked) {
							continue;
						}
						picked_any = true;
						if (row.needs_upgrade) {
							upgrade_picked = true;
						}
					}
					this.update.sensitive = picked_any;
					this.upgrade.visible = upgrade_any;
					this.upgrade.sensitive = upgrade_picked;
					var listed_total = this.listed.get_n_items();
					var all = listed_total > 0;
					for (var i = (uint) 0; i < listed_total; i++) {
						var row = (Argus.Controller.Dialog.UpgradeTarget) this.listed.get_item(i);
						if (!row.picked) {
							all = false;
							break;
						}
					}
					if (all) {
						this.select.label = "Select none";
					} else {
						this.select.label = "Select all";
					}
				});
				this.rows.append(target);
			}
			var first = "deb";
			if (deb_count < 1 && rpm_count > 0) {
				first = "rpm";
				upgrade_count = 0;
				var total = this.rows.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Controller.Dialog.UpgradeTarget) this.rows.get_item(i);
					if (row.kind == "rpm" && row.needs_upgrade) {
						upgrade_count++;
					}
				}
			}
			this.search.text = "";
			this.select.label = "Select all";
			this.filling = true;
			this.platforms.active_name = first;
			this.filling = false;
			this.filter.search = "";
			this.filter.kind = first;
			this.update.sensitive = false;
			this.upgrade.visible = upgrade_count > 0;
			this.upgrade.sensitive = false;
			this.showing = true;
			this.present(parent);
		}
	}
}
