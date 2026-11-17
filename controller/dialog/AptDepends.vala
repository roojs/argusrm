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
	 * Packages removed with one Debian package.
	 *
	 * Holding Remove on the Debian Software grid opens this. The
	 * grid is {@link Argus.Controller.Store.AptDepends}. Search
	 * filters by package name. Cancel closes the dialog. Start the
	 * task now stays off until a remove task exists.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.AptDepends(app);
	 * dialog.open(window, "libc6");
	 * }}}
	 */
	public class AptDepends : Adw.Dialog
	{
		public Argus.Controller.Application app;
		private Argus.Controller.Store.AptDepends store;
		private Argus.Controller.Filters.AptDepends filter;
		private Gtk.SearchEntry search;
		private Gtk.Stack body;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }

		/**
		 * @param app the controller process
		 */
		public AptDepends(Argus.Controller.Application app)
		{
			Object(
				title: "Remove",
				content_width: 880,
				content_height: 520
			);
			this.app = app;
			this.store = new Argus.Controller.Store.AptDepends(app);
			this.filter = new Argus.Controller.Filters.AptDepends();
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
			var names = new Gtk.SignalListItemFactory();
			names.setup.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				item.child = new Gtk.Label("") {
					xalign = 0,
					hexpand = true,
					ellipsize = Pango.EllipsizeMode.END
				};
			});
			names.bind.connect((obj) => {
				var item = (Gtk.ListItem) obj;
				var row = (Argus.Shared.SQV.AptDepends) item.item;
				var label = (Gtk.Label) item.child;
				label.label = row.name;
				label.tooltip_text = row.name;
			});
			var name_expr = new Gtk.PropertyExpression(
				typeof(Argus.Shared.SQV.AptDepends), null, "name");
			grid.append_column(new Gtk.ColumnViewColumn("Package", names) {
				expand = true,
				resizable = true,
				sorter = new Gtk.StringSorter(name_expr) {
					ignore_case = true
				}
			});
			this.search = new Gtk.SearchEntry() {
				placeholder_text = "Search packages",
				hexpand = true
			};
			var empty_label = new Gtk.Label("No packages") {
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
			this.body.add_named(empty_label, "empty");
			var cancel = new Gtk.Button.with_label("Cancel");
			var start = new Gtk.Button.with_label("Start the task now") {
				css_classes = { "suggested-action" },
				sensitive = false
			};
			var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
				halign = Gtk.Align.END
			};
			actions.append(cancel);
			actions.append(start);
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			box.append(this.search);
			box.append(this.body);
			box.append(actions);
			this.child = box;
			cancel.clicked.connect(() => {
				this.close();
			});
			this.search.search_changed.connect(() => {
				this.filter.search = this.search.text;
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
			this.closed.connect(() => {
				this.showing = false;
			});
		}

		/**
		 * Show the dialog and load packages removed with ''name''.
		 *
		 * @param parent window the dialog is attached to
		 * @param name package being removed
		 */
		public void open(Gtk.Widget parent, string name)
		{
			if (this.showing) {
				return;
			}
			this.title = name;
			this.search.text = "";
			this.filter.search = "";
			this.showing = true;
			this.present(parent);
			this.store.load(name);
		}
	}
}
