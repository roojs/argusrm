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
	 * Tabbed detail pane shown under the Machines grid.
	 *
	 * Constructs the three per-machine package tabs ({@link DebPackages},
	 * {@link RpmPackages}, {@link Programs}) upfront and shows only the
	 * one matching the selected machine's
	 * {@link Argus.Shared.OSQuery.SystemInfo.package_manager}. Tabs
	 * lazy-load when visible for the current machine.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var detail = new Argus.Controller.Tab.Asset.Machine.Detail(window);
	 * detail.show_machine(machine);
	 * }}}
	 */
	public class Detail : Gtk.Box
	{
		private Adw.ToggleGroup group;
		private Adw.ViewStack pages;
		private Gtk.Box bar;
		private Adw.Toggle debian_toggle;
		private Adw.Toggle rpm_toggle;
		private Adw.Toggle windows_toggle;
		private DebPackages debian;
		private RpmPackages rpm;
		private Programs windows;
		private int current_agent_id = 0;
		private Argus.Shared.OSQuery.PackageManager current_pm = Argus.Shared.OSQuery.PackageManager.UNKNOWN;
		private bool has_pm = false;
		private bool debian_loaded = false;
		private bool rpm_loaded = false;
		private bool windows_loaded = false;

		/**
		 * Build the per-machine tab switcher and stacked detail pages.
		 *
		 * @param window the controller window this detail pane belongs to
		 */
		public Detail(Argus.Controller.Window window)
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.hexpand = true;
			this.vexpand = true;
			this.pages = new Adw.ViewStack() {
				hexpand = true,
				vexpand = true
			};
			this.group = new Adw.ToggleGroup() {
				orientation = Gtk.Orientation.HORIZONTAL,
				homogeneous = true,
				hexpand = true
			};
			this.group.add_css_class("both");
			this.debian = new DebPackages(window);
			this.pages.add_titled_with_icon(
				this.debian, "debian", "Debian packages", "emblem-debian-symbolic");
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
			this.debian_toggle = new Adw.Toggle() {
				name = "debian",
				child = new Gtk.CenterBox() {
					center_widget = debian_row,
					end_widget = debian_spin,
					hexpand = true
				}
			};
			this.debian.bind_property("refreshing", debian_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.debian.bind_property("refreshing", debian_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			this.rpm = new RpmPackages(window);
			this.pages.add_titled_with_icon(
				this.rpm, "rpm", "RPM packages", "application-x-rpm");
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
			this.rpm_toggle = new Adw.Toggle() {
				name = "rpm",
				child = new Gtk.CenterBox() {
					center_widget = rpm_row,
					end_widget = rpm_spin,
					hexpand = true
				}
			};
			this.rpm.bind_property("refreshing", rpm_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.rpm.bind_property("refreshing", rpm_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			this.windows = new Programs(window);
			this.pages.add_titled_with_icon(
				this.windows, "windows", "Windows programs", "windows-symbolic");
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
			windows_row.append(new Gtk.Label("Windows programs"));
			this.windows_toggle = new Adw.Toggle() {
				name = "windows",
				child = new Gtk.CenterBox() {
					center_widget = windows_row,
					end_widget = windows_spin,
					hexpand = true
				}
			};
			this.windows.bind_property("refreshing", windows_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.windows.bind_property("refreshing", windows_spin, "spinning", GLib.BindingFlags.SYNC_CREATE);
			this.pages.add_named(new Adw.StatusPage() {
				title = "No packages",
				description = "Package listing is not available for this operating system.",
				icon_name = "package-x-generic-symbolic",
				vexpand = true
			}, "unknown");
			this.group.notify["active-name"].connect(() => {
				var name = this.group.active_name;
				if (name == null || name == "") {
					return;
				}
				this.pages.visible_child_name = name;
				if (this.current_agent_id < 1) {
					return;
				}
				switch (name) {
					case "debian":
						if (!this.debian_loaded) {
							this.debian_loaded = true;
							this.debian.load(this.current_agent_id);
						}
						break;

					case "rpm":
						if (!this.rpm_loaded) {
							this.rpm_loaded = true;
							this.rpm.load(this.current_agent_id);
						}
						break;

					case "windows":
						if (!this.windows_loaded) {
							this.windows_loaded = true;
							this.windows.load(this.current_agent_id);
						}
						break;

					default:
						break;
				}
			});
			this.bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 6,
				margin_bottom = 6
			};
			this.bar.append(this.group);
			this.append(this.bar);
			this.append(this.pages);
		}

		/**
		 * Clear the active machine selection state.
		 */
		public void clear()
		{
			this.current_agent_id = 0;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
		}

		/**
		 * Update visible package tabs and load the active tab for
		 * ''machine''.
		 *
		 * @param machine selected row from the Machines grid
		 */
		public void show_machine(Argus.Shared.OSQuery.SystemInfo machine)
		{
			var agent_id = (int) machine.agent_id;
			if (agent_id < 1) {
				this.clear();
				return;
			}
			this.current_agent_id = agent_id;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			var pm = machine.package_manager();
			if (!this.has_pm || pm != this.current_pm) {
				this.has_pm = true;
				this.current_pm = pm;
				this.group.remove_all();
				switch (pm) {
					case Argus.Shared.OSQuery.PackageManager.APT:
						this.bar.visible = true;
						this.group.add(this.debian_toggle);
						this.group.active_name = "debian";
						break;

					case Argus.Shared.OSQuery.PackageManager.DNF:
						this.bar.visible = true;
						this.group.add(this.rpm_toggle);
						this.group.active_name = "rpm";
						break;

					case Argus.Shared.OSQuery.PackageManager.WIN:
						this.bar.visible = true;
						this.group.add(this.windows_toggle);
						this.group.active_name = "windows";
						break;

					default:
						this.bar.visible = false;
						this.pages.visible_child_name = "unknown";
						return;
				}
			}
			switch (pm) {
				case Argus.Shared.OSQuery.PackageManager.APT:
					this.pages.visible_child_name = "debian";
					if (!this.debian_loaded) {
						this.debian_loaded = true;
						this.debian.load(agent_id);
					}
					break;

				case Argus.Shared.OSQuery.PackageManager.DNF:
					this.pages.visible_child_name = "rpm";
					if (!this.rpm_loaded) {
						this.rpm_loaded = true;
						this.rpm.load(agent_id);
					}
					break;

				case Argus.Shared.OSQuery.PackageManager.WIN:
					this.pages.visible_child_name = "windows";
					if (!this.windows_loaded) {
						this.windows_loaded = true;
						this.windows.load(agent_id);
					}
					break;

				default:
					this.pages.visible_child_name = "unknown";
					break;
			}
		}
	}
}
