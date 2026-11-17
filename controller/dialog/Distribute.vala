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
	 * Installer dialog for one distributable.
	 *
	 * A double-click or a long press on the Distributables grid
	 * opens this. The grid is {@link Argus.Controller.Store.Distribute}.
	 * Search filters by machine name or logged-in user. Select all
	 * ticks the machines currently listed. Cancel closes the dialog.
	 * Start the task now asks
	 * {@link Argus.Controller.Store.Distribute.selected} for the ticked
	 * rows, then {@link Argus.Controller.Store.Distributable.submit}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.Distribute(app, store);
	 * dialog.open(window, row);
	 * }}}
	 */
	public class Distribute : Adw.Dialog
	{
		public Argus.Controller.Application app;
		private Argus.Controller.Store.Distribute store;
		private Argus.Controller.Store.Distributable products;
		private Argus.Controller.Filters.Distribute filter;
		private Argus.Shared.SQT.Distributable product = new Argus.Shared.SQT.Distributable();
		private Gtk.SearchEntry search;
		private Gtk.FilterListModel listed;
		private Gtk.Button start;
		private Gtk.Label empty_label;
		private Gtk.Stack body;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }

		/**
		 * @param app the controller process
		 * @param products the distributable list that creates the task
		 */
		public Distribute(Argus.Controller.Application app, Argus.Controller.Store.Distributable products)
		{
			Object(title: "Install", content_width: 880, content_height: 520);
			this.app = app;
			this.products = products;
			this.store = new Argus.Controller.Store.Distribute(app);
			this.filter = new Argus.Controller.Filters.Distribute();
			this.listed = new Gtk.FilterListModel(this.store, this.filter) {
				incremental = true
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
				var row = (Argus.Shared.SQV.DistributeMachine) item.item;
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
				var row = (Argus.Shared.SQV.DistributeMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.machine;
				label.tooltip_text = row.machine;
			});
			var machine_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.DistributeMachine), null, "machine");
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
				var row = (Argus.Shared.SQV.DistributeMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.logged_in_users;
				label.tooltip_text = row.logged_in_users;
			});
			var users_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.DistributeMachine), null, "logged-in-users");
			grid.append_column(new Gtk.ColumnViewColumn("Logged in users", users) {
				fixed_width = 160,
				resizable = true,
				sorter = new Gtk.StringSorter(users_expr) {
					ignore_case = true
				}
			});
			var existing = new Gtk.SignalListItemFactory();
			existing.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					width_request = 180
				};
			});
			existing.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQV.DistributeMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.existing;
				label.tooltip_text = row.existing;
			});
			var existing_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.DistributeMachine), null, "existing");
			grid.append_column(new Gtk.ColumnViewColumn("Existing", existing) {
				fixed_width = 180,
				resizable = true,
				sorter = new Gtk.StringSorter(existing_expr) {
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
				var row = (Argus.Shared.SQV.DistributeMachine) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.version;
				label.tooltip_text = row.version;
			});
			var version_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.DistributeMachine), null, "version");
			grid.append_column(new Gtk.ColumnViewColumn("Version", versions) {
				fixed_width = 180,
				resizable = true,
				sorter = new Gtk.StringSorter(version_expr) {
					ignore_case = true
				}
			});
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search machines or users",
				hexpand = true
			};
			var select_all = new Gtk.Button.with_label("Select all") {
				halign = Gtk.Align.END
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
			this.start = new Gtk.Button.with_label("Start the task now") {
				css_classes = { "suggested-action" },
				sensitive = false
			};
			var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END
			};
			actions.append(cancel);
			actions.append(this.start);
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
			bar.append(this.search);
			bar.append(select_all);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			box.append(bar);
			box.append(this.body);
			box.append(actions);
			this.child = box;
			cancel.clicked.connect(() => {
				this.close();
			});
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
			});
			select_all.clicked.connect(() => {
				var total = this.listed.get_n_items();
				for (var i = (uint) 0; i < total; i++) {
					var row = (Argus.Shared.SQV.DistributeMachine) this.listed.get_item(i);
					row.picked = true;
				}
			});
			this.start.clicked.connect(() => {
				var ids = new Gee.ArrayList<int>();
				foreach (var row in this.store.selected()) {
					ids.add((int) row.agent_id);
				}
				this.products.submit(this.product, ids);
			});
			this.store.notify["picked"].connect(() => {
				if (this.products.submitting || this.store.picked < 1) {
					this.start.sensitive = false;
					return;
				}
				this.start.sensitive = this.product.version_id > 0 && this.product.filename != "";
			});
			this.products.notify["submitting"].connect(() => {
				if (this.products.submitting || this.store.picked < 1) {
					this.start.sensitive = false;
					return;
				}
				this.start.sensitive = this.product.version_id > 0 && this.product.filename != "";
			});
			this.store.notify["busy"].connect(() => {
				if (this.store.busy) {
					this.body.visible_child_name = "wait";
					return;
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
			this.products.failed.connect((heading, message) => {
				if (!this.showing) {
					return;
				}
				var notice = new Argus.Shared.Notice(heading, message);
				notice.add_response("ok", "OK");
				notice.present(this);
			});
			this.closed.connect(() => {
				this.showing = false;
			});
		}

		/**
		 * Show the dialog and load machines for ''row''.
		 *
		 * @param parent window the dialog is attached to
		 * @param row product whose latest version will be installed
		 */
		public void open(Gtk.Widget parent, Argus.Shared.SQT.Distributable row)
		{
			if (this.showing) {
				return;
			}
			this.product = row;
			this.title = row.name;
			this.empty_label.label = "No " + row.platform + " machines";
			this.search.text = "";
			this.filter.search = "";
			this.showing = true;
			this.present(parent);
			this.store.load(row.name, row.platform, row.version);
		}
	}
}
