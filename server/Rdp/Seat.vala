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

namespace Argus.Server.Rdp
{
	/**
	 * One machine's desktop stream.
	 *
	 * {@link Relay} keeps one of these per agent id. The agent
	 * stream and the controller view are the two sides. ''asked''
	 * is the controller app connection waiting for ''relay.ready''.
	 * ''holding'' is a ''Relay.view'' waiting for {@link release}.
	 * A forwarded byte sets {@link begun}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var seat = new Argus.Server.Rdp.Seat();
	 * seat.asked = caller;
	 * seat.joined(request, agent_id);
	 * }}}
	 */
	public class Seat : GLib.Object
	{
		internal OLLMrpc.Transport.Connection? agent_conn;
		internal OLLMrpc.Transport.Connection? view_conn;
		internal OLLMrpc.Transport.Connection? asked;
		internal OLLMrpc.Transport.Connection? watcher;
		internal OLLMrpc.Request? holding;
		internal int agent_id;
		private bool begun;
		private bool forwarded;
		private bool dropped;

		/**
		 * Store the agent stream and answer the controller that asked.
		 *
		 * @param request inbound ''Relay.join'' on the agent stream
		 * @param agent_id ''agent.id'' of the machine
		 */
		public void joined(OLLMrpc.Request request, int agent_id)
		{
			this.agent_conn = request.connection;
			this.agent_id = agent_id;
			request.reply(new OLLMrpc.Response());
			if (this.watcher != null) {
				GLib.debug("relay.status %s %d", Argus.Rdp.State.SUCCESS_MACHINE_JOINED_RELAY.to_string(), 0);
				this.watcher.write(new OLLMrpc.Notification() {
					method = "relay.status",
					args = OLLMrpc.args("iii", this.agent_id, (int) Argus.Rdp.State.SUCCESS_MACHINE_JOINED_RELAY, 0)
				});
				GLib.debug("relay.status %s %d", Argus.Rdp.State.REQUEST_SERVER_AWAIT_VIEW.to_string(), 0);
				this.watcher.write(new OLLMrpc.Notification() {
					method = "relay.status",
					args = OLLMrpc.args("iii", this.agent_id, (int) Argus.Rdp.State.REQUEST_SERVER_AWAIT_VIEW, 0)
				});
				GLib.debug("relay.status %s %d", Argus.Rdp.State.SUCCESS_SERVER_AWAITING_VIEW.to_string(), 0);
				this.watcher.write(new OLLMrpc.Notification() {
					method = "relay.status",
					args = OLLMrpc.args("iii", this.agent_id, (int) Argus.Rdp.State.SUCCESS_SERVER_AWAITING_VIEW, 0)
				});
			}
			if (this.asked == null) {
				return;
			}
			this.asked.write(new OLLMrpc.Notification() {
				method = "relay.ready",
				args = OLLMrpc.args("i", agent_id)
			});
			this.asked = null;
		}

		/**
		 * Store this view.
		 *
		 * Nothing has been forwarded yet, so the reply goes now.
		 *
		 * @param request the controller's second connection
		 * @return true when a byte has already moved and the reply waits
		 */
		public bool attach(OLLMrpc.Request request)
		{
			this.view_conn = request.connection;
			if (this.begun) {
				return true;
			}
			request.reply(new OLLMrpc.Response());
			return false;
		}

		/**
		 * This Windows connection is the start.
		 *
		 * A held view is answered. The next forwarded byte is the
		 * first byte of that connection.
		 */
		public void release()
		{
			this.begun = false;
			if (this.holding == null) {
				return;
			}
			var held = this.holding;
			this.holding = null;
			held.reply(new OLLMrpc.Response());
		}

		/**
		 * Copy one chunk to the other side of this seat.
		 *
		 * A cut that is still waiting drops the chunk. An empty
		 * chunk is not a forwarded byte.
		 *
		 * @param from the connection that sent the chunk
		 * @param chunk desktop bytes
		 */
		public void forward(OLLMrpc.Transport.Connection from, GLib.Bytes chunk)
		{
			if (this.holding != null) {
				return;
			}
			var other = this.agent_conn;
			if (from == this.agent_conn) {
				other = this.view_conn;
			}
			if (other == null || chunk.get_size() == 0) {
				if (!this.begun || other != null || this.dropped) {
					return;
				}
				this.dropped = true;
				if (this.watcher == null) {
					return;
				}
				GLib.debug("relay.status %s %d", Argus.Rdp.State.RETRY_RELAY_FORWARDING_DROPPED.to_string(), 1);
				this.watcher.write(new OLLMrpc.Notification() {
					method = "relay.status",
					args = OLLMrpc.args("iii", this.agent_id, (int) Argus.Rdp.State.RETRY_RELAY_FORWARDING_DROPPED, 1)
				});
				return;
			}
			var held = GLib.Value(typeof(GLib.Bytes));
			held.set_boxed(chunk);
			var note = new OLLMrpc.Notification() {
				method = "relay.data"
			};
			note.args.add(held);
			other.write(note);
			this.begun = true;
			if (this.forwarded || this.watcher == null) {
				this.forwarded = true;
				return;
			}
			this.forwarded = true;
			GLib.debug("relay.status %s %d", Argus.Rdp.State.SUCCESS_RELAY_FORWARDING.to_string(), 0);
			this.watcher.write(new OLLMrpc.Notification() {
				method = "relay.status",
				args = OLLMrpc.args("iii", this.agent_id, (int) Argus.Rdp.State.SUCCESS_RELAY_FORWARDING, 0)
			});
		}
	}
}
