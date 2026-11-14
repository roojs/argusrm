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
	 * Displays per-machine {@link LoggedInUsers}, the relevant package
	 * tab ({@link DebPackages}, {@link RpmPackages}, or
	 * {@link Programs}) for the selected machine's
	 * {@link Argus.Shared.OSQuery.SystemInfo.package_manager},
	 * {@link InterfaceAddresses}, and {@link CpuInfo}. Tabs lazy-load
	 * when visible for the current machine.
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
		private Adw.Toggle users_toggle;
		private Adw.Toggle debian_toggle;
		private Adw.Toggle rpm_toggle;
		private Adw.Toggle windows_toggle;
		private Adw.Toggle interfaces_toggle;
		private Adw.Toggle cpus_toggle;
		private LoggedInUsers users;
		private DebPackages debian;
		private RpmPackages rpm;
		private Programs windows;
		private InterfaceAddresses interfaces;
		private CpuInfo cpus;
		private int current_agent_id = 0;
		private Argus.Shared.OSQuery.PackageManager current_pm = Argus.Shared.OSQuery.PackageManager.UNKNOWN;
		private bool has_pm = false;
		private bool users_loaded = false;
		private bool debian_loaded = false;
		private bool rpm_loaded = false;
		private bool windows_loaded = false;
		private bool interfaces_loaded = false;
		private bool cpus_loaded = false;

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
			this.users = new LoggedInUsers(window);
			this.pages.add_titled_with_icon(
				this.users, "users", "Users", "system-users-symbolic");
			var users_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var users_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			users_row.append(new Gtk.Image.from_icon_name("system-users-symbolic"));
			users_row.append(new Gtk.Label("Users"));
			this.users_toggle = new Adw.Toggle() {
				name = "users",
				child = new Gtk.CenterBox() {
					center_widget = users_row,
					end_widget = users_spin,
					hexpand = true
				}
			};
			this.users.bind_property("refreshing", users_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.debian = new DebPackages(window);
			this.pages.add_titled_with_icon(
				this.debian, "debian", "Debian packages", "emblem-debian-symbolic");
			var debian_spin = new Adw.Spinner() {
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
			this.rpm = new RpmPackages(window);
			this.pages.add_titled_with_icon(
				this.rpm, "rpm", "RPM packages", "application-x-rpm-symbolic");
			var rpm_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var rpm_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			rpm_row.append(new Gtk.Image.from_icon_name("application-x-rpm-symbolic"));
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
			this.windows = new Programs(window);
			this.pages.add_titled_with_icon(
				this.windows, "windows", "Windows programs", "windows-symbolic");
			var windows_spin = new Adw.Spinner() {
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
			this.interfaces = new InterfaceAddresses(window);
			this.pages.add_titled_with_icon(
				this.interfaces, "interfaces", "Interfaces", "network-wired-symbolic");
			var interfaces_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var interfaces_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			interfaces_row.append(new Gtk.Image.from_icon_name("network-wired-symbolic"));
			interfaces_row.append(new Gtk.Label("Interfaces"));
			this.interfaces_toggle = new Adw.Toggle() {
				name = "interfaces",
				child = new Gtk.CenterBox() {
					center_widget = interfaces_row,
					end_widget = interfaces_spin,
					hexpand = true
				}
			};
			this.interfaces.bind_property("refreshing", interfaces_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
			this.cpus = new CpuInfo(window);
			this.pages.add_titled_with_icon(
				this.cpus, "cpus", "CPUs", "computer-symbolic");
			var cpus_spin = new Adw.Spinner() {
				visible = false,
				halign = Gtk.Align.END,
				valign = Gtk.Align.CENTER
			};
			var cpus_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			cpus_row.append(new Gtk.Image.from_icon_name("computer-symbolic"));
			cpus_row.append(new Gtk.Label("CPUs"));
			this.cpus_toggle = new Adw.Toggle() {
				name = "cpus",
				child = new Gtk.CenterBox() {
					center_widget = cpus_row,
					end_widget = cpus_spin,
					hexpand = true
				}
			};
			this.cpus.bind_property("refreshing", cpus_spin, "visible", GLib.BindingFlags.SYNC_CREATE);
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
					case "users":
						if (this.users_loaded) {
							break;
						}
						this.users_loaded = true;
						this.users.load(this.current_agent_id);
						break;

					case "debian":
						if (this.debian_loaded) {
							break;
						}
						this.debian_loaded = true;
						this.debian.load(this.current_agent_id);
						break;

					case "rpm":
						if (this.rpm_loaded) {
							break;
						}
						this.rpm_loaded = true;
						this.rpm.load(this.current_agent_id);
						break;

					case "windows":
						if (this.windows_loaded) {
							break;
						}
						this.windows_loaded = true;
						this.windows.load(this.current_agent_id);
						break;

					case "interfaces":
						if (this.interfaces_loaded) {
							break;
						}
						this.interfaces_loaded = true;
						this.interfaces.load(this.current_agent_id);
						break;

					case "cpus":
						if (this.cpus_loaded) {
							break;
						}
						this.cpus_loaded = true;
						this.cpus.load(this.current_agent_id);
						break;

					default:
						break;
				}
			});
			this.bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
				margin_start = 12,
				margin_end = 12,
				margin_top = 4,
				margin_bottom = 4
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
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
		}

		/**
		 * Update visible detail tabs and load the active tab for
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
			this.current_agent_id = 0;
			this.users_loaded = false;
			this.debian_loaded = false;
			this.rpm_loaded = false;
			this.windows_loaded = false;
			this.interfaces_loaded = false;
			this.cpus_loaded = false;
			var pm = machine.package_manager();
			if (!this.has_pm || pm != this.current_pm) {
				this.has_pm = true;
				this.current_pm = pm;
				var previous = "";
				if (this.group.active_name != null) {
					previous = this.group.active_name;
				}
				var pkg_tab = "";
				while (this.group.n_toggles > 0) {
					var toggle = this.group.get_toggle(0);
					if (toggle == null) {
						break;
					}
					this.group.remove(toggle);
				}
				this.group.add(this.users_toggle);
				switch (pm) {
					case Argus.Shared.OSQuery.PackageManager.APT:
						this.group.add(this.debian_toggle);
						pkg_tab = "debian";
						break;

					case Argus.Shared.OSQuery.PackageManager.DNF:
						this.group.add(this.rpm_toggle);
						pkg_tab = "rpm";
						break;

					case Argus.Shared.OSQuery.PackageManager.WIN:
						this.group.add(this.windows_toggle);
						pkg_tab = "windows";
						break;

					default:
						break;
				}
				this.group.add(this.interfaces_toggle);
				this.group.add(this.cpus_toggle);
				var target = "users";
				switch (previous) {
					case "users":
					case "interfaces":
					case "cpus":
						target = previous;
						break;

					case "debian":
					case "rpm":
					case "windows":
						if (pkg_tab != "") {
							target = pkg_tab;
						}
						break;

					default:
						break;
				}
				this.group.active_name = target;
			}
			this.current_agent_id = agent_id;
			var active = "users";
			if (this.group.active_name != null) {
				active = this.group.active_name;
			}
			this.pages.visible_child_name = active;
			switch (active) {
				case "users":
					if (this.users_loaded) {
						break;
					}
					this.users_loaded = true;
					this.users.load(agent_id);
					break;

				case "debian":
					if (this.debian_loaded) {
						break;
					}
					this.debian_loaded = true;
					this.debian.load(agent_id);
					break;

				case "rpm":
					if (this.rpm_loaded) {
						break;
					}
					this.rpm_loaded = true;
					this.rpm.load(agent_id);
					break;

				case "windows":
					if (this.windows_loaded) {
						break;
					}
					this.windows_loaded = true;
					this.windows.load(agent_id);
					break;

				case "interfaces":
					if (this.interfaces_loaded) {
						break;
					}
					this.interfaces_loaded = true;
					this.interfaces.load(agent_id);
					break;

				case "cpus":
					if (this.cpus_loaded) {
						break;
					}
					this.cpus_loaded = true;
					this.cpus.load(agent_id);
					break;

				default:
					break;
			}
		}
	}
}
