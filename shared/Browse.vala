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

namespace Argus.Shared
{
	/**
	 * Broadcast browse for Argus registration.
	 *
	 * Same result as ''PairBrowse'': service ''_rpc._tcp'', TXT
	 * ''id'', then host and port. {@link poll} is empty while
	 * waiting, ''none'' when browse fails, or the id, a newline,
	 * and ''host:port''. This file is the Linux Avahi browse.
	 * Windows is ''shared/windows/Browse.vala''. Android is
	 * ''shared/android/Browse.vala''.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var browse = new Argus.Shared.Browse();
	 * browse.start();
	 * var line = browse.poll();
	 * browse.stop();
	 * }}}
	 */
	public class Browse : GLib.Object
	{
		/**
		 * Latest line from {@link poll}. Empty until a service
		 * with TXT ''id'' is found, or ''none'' after a failure.
		 */
		private string found = "";
		private bool client_up = false;
		private bool browser_up = false;
		private Avahi.Client client = new Avahi.Client(Avahi.ClientFlags.NO_FAIL);
		private Avahi.ServiceBrowser browser = new Avahi.ServiceBrowser("_rpc._tcp");
		private Gee.ArrayList<Avahi.ServiceResolver> resolvers {
			get; set; default = new Gee.ArrayList<Avahi.ServiceResolver>();
		}

		/**
		 * Begin browsing for ''_rpc._tcp''.
		 *
		 * A later {@link poll} returns the first service whose TXT
		 * record has an ''id''. A failure sets that result to
		 * ''none''. Calling this again does nothing.
		 */
		public void start()
		{
			if (this.client_up) {
				return;
			}
			this.found = "";
			this.client_up = true;
			GLib.debug("browsing _rpc._tcp");
			GLib.SourceFunc open_browser = () => {
				if (this.browser_up || this.found == "none") {
					return false;
				}
				this.browser = new Avahi.ServiceBrowser("_rpc._tcp");
				try {
					this.browser.attach(this.client);
				} catch (Avahi.Error e) {
					GLib.warning("%s", e.message);
					this.found = "none";
					return false;
				}
				this.browser_up = true;
				this.browser.new_service.connect((iface, protocol, name, type, domain) => {
					GLib.debug("service %s", name);
					if (this.found != "") {
						return;
					}
					var resolver = new Avahi.ServiceResolver(iface, protocol, name, type,
						domain, Avahi.Protocol.INET);
					try {
						resolver.attach(this.client);
					} catch (Avahi.Error e) {
						GLib.warning("%s", e.message);
						return;
					}
					this.resolvers.add(resolver);
					resolver.found.connect((riface, rprotocol, rname, rtype, rdomain,
						hostname, address, port, txt) => {
						if (this.found != "") {
							return;
						}
						if (address == null || txt == null) {
							GLib.debug("resolved %s missing address or txt", rname);
							return;
						}
						GLib.debug("resolved %s %s:%u", rname, address.to_string(), (uint) port);
						unowned Avahi.StringList? list = txt;
						while (list != null) {
							var entry = (string) list.text;
							var eq = entry.index_of("=");
							if (eq < 1 || entry.substring(0, eq) != "id") {
								list = list.next;
								continue;
							}
							var id = entry.substring(eq + 1);
							if (id == "") {
								list = list.next;
								continue;
							}
							this.found = id + "\n" + address.to_string() + ":" + port.to_string();
							GLib.debug("broadcast %s", this.found.replace("\n", " "));
							return;
						}
						GLib.debug("resolved %s has no id", rname);
					});
					resolver.failure.connect((err) => {
						GLib.warning("%s", err.message);
					});
				});
				this.browser.all_for_now.connect(() => {
					GLib.debug("browse cache complete");
				});
				this.browser.failure.connect((err) => {
					GLib.warning("%s", err.message);
					this.found = "none";
				});
				return false;
			};
			this.client.state_changed.connect((state) => {
				switch (state) {
					case Avahi.ClientState.FAILURE:
						GLib.warning("broadcast browse failed");
						this.found = "none";
						return;
					case Avahi.ClientState.S_RUNNING:
						GLib.debug("browse client running");
						open_browser();
						return;
					case Avahi.ClientState.NOT_STARTED:
						GLib.debug("browse client not started");
						return;
					case Avahi.ClientState.S_REGISTERING:
						GLib.debug("browse client registering");
						return;
					case Avahi.ClientState.S_COLLISION:
						GLib.debug("browse client collision");
						return;
					case Avahi.ClientState.CONNECTING:
						GLib.debug("browse client connecting");
						return;
					default:
						return;
				}
			});
			try {
				this.client.start();
			} catch (Avahi.Error e) {
				GLib.warning("%s", e.message);
				this.found = "none";
				return;
			}
			if (this.client.state == Avahi.ClientState.S_RUNNING) {
				GLib.debug("browse client running");
				open_browser();
			}
		}

		/**
		 * Latest browse line.
		 *
		 * Empty while waiting. ''none'' when browse failed.
		 * Otherwise the id, a newline, and ''host:port''.
		 *
		 * @return the line described above
		 */
		public string poll()
		{
			return this.found;
		}

		/**
		 * Stop browsing.
		 *
		 * A result already stored for {@link poll} stays. Calling
		 * this before {@link start} does nothing.
		 */
		public void stop()
		{
			if (!this.browser_up) {
				return;
			}
			this.browser_up = false;
			this.browser = new Avahi.ServiceBrowser("_rpc._tcp");
			this.resolvers.clear();
		}
	}
}
