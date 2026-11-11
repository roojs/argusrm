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
	 * Software half of the Assets page.
	 *
	 * Three sub-tabs. Each one has its own grid and loads its
	 * own table. Debian packages, RPM packages, and Windows.
	 * Each tab has an icon and a spinner. The icon and the label
	 * sit in the middle of the tab. The spinner stays at the end.
	 * This row is an inline switcher: a grey bar, the active tab
	 * white, a light border. It spans the window. The window
	 * header stays the title.
	 * An empty grid shows its spinner over the grid. A later
	 * load keeps the rows and spins in that tab.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var page = new Argus.Controller.Tab.Asset.Software(window);
	 * }}}
	 */
	public class Software : Gtk.Box
	{
		/**
		 * Build the three package grids.
		 *
		 * @param window the controller window this page belongs to
		 */
		public Software(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			var pages = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true
			};
			var group = new Adw.ToggleGroup() {
				orientation = Gtk.Orientation.HORIZONTAL,
				homogeneous = true,
				hexpand = true
			};
			group.add_css_class("both");
			var debian = new DebPackages(window);
			pages.add_titled_with_icon(debian, "debian", "Debian packages", "emblem-debian-symbolic");
			var debian_spin = new Gtk.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var debian_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			debian_row.append(new Gtk.Image.from_icon_name("emblem-debian-symbolic"));
			debian_row.append(new Gtk.Label("Debian packages"));
			group.add(new Adw.Toggle() {
				name = "debian",
				child = new Gtk.CenterBox() {
					center_widget = debian_row,
					end_widget = debian_spin,
					hexpand = true
				}
			});
			debian.bind_property("refreshing", debian_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			debian.bind_property("refreshing", debian_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			var rpm = new RpmPackages(window);
			pages.add_titled_with_icon(rpm, "rpm", "RPM packages", "application-x-rpm");
			var rpm_spin = new Gtk.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var rpm_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			rpm_row.append(new Gtk.Image.from_icon_name("application-x-rpm"));
			rpm_row.append(new Gtk.Label("RPM packages"));
			group.add(new Adw.Toggle() {
				name = "rpm",
				child = new Gtk.CenterBox() {
					center_widget = rpm_row,
					end_widget = rpm_spin,
					hexpand = true
				}
			});
			rpm.bind_property("refreshing", rpm_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			rpm.bind_property("refreshing", rpm_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			var windows = new Programs(window);
			pages.add_titled_with_icon(windows, "windows", "Windows", "windows-symbolic");
			var windows_spin = new Gtk.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var windows_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			windows_row.append(new Gtk.Image.from_icon_name("windows-symbolic"));
			windows_row.append(new Gtk.Label("Windows"));
			group.add(new Adw.Toggle() {
				name = "windows",
				child = new Gtk.CenterBox() {
					center_widget = windows_row,
					end_widget = windows_spin,
					hexpand = true
				}
			});
			windows.bind_property("refreshing", windows_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			windows.bind_property("refreshing", windows_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			group.notify["active-name"].connect(() => {
				var name = group.active_name;
				if (name == null || name == "") {
					return;
				}
				pages.visible_child_name = name;
			});
			group.active_name = "debian";
			var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			bar.set_css_name("inline-view-switcher");
			bar.append(group);
			bar.margin_start = 12;
			bar.margin_end = 12;
			bar.margin_top = 6;
			bar.margin_bottom = 6;
			this.append(bar);
			this.append(pages);
		}
	}
}
