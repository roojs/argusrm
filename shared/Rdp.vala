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

/**
 * Remote desktop progress shared by the agent, the server, and the controller.
 *
 * {@link State} is the wire value for one step of Take control. The
 * notification carries the enum, not a sentence. {@link State.to_string}
 * is the sentence. {@link State.line} adds the attempt count.
 * The log prints that same sentence.
 *
 * == Example ==
 *
 * {{{
 * var state = Argus.Rdp.State.SUCCESS_ASKED_MACHINE;
 * stderr.printf("%s\n", state.to_string());
 * toast(state.line(0));
 * }}}
 */
namespace Argus.Rdp
{
	/**
	 * One step of opening a remote desktop.
	 *
	 * Names sit in the order the connection reaches them. A blank
	 * line in the source is the next step. {@link REQUEST_} is the
	 * step being asked for. {@link SUCCESS_} is that step finished.
	 * {@link FAIL_} stops, because trying again will not help.
	 * {@link RETRY_} is the same failure with the next attempt number.
	 * The page calls {@link line}. It does not keep its own sentences.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var text = Argus.Rdp.State.RETRY_MACHINE_DOWN.line(1);
	 * }}}
	 */
	public enum State {
		REQUEST_TAKE_CONTROL,
		SUCCESS_TAKE_CONTROL,
		FAIL_NO_MACHINE,

		REQUEST_START_DESKTOP,
		SUCCESS_START_DESKTOP,
		RETRY_SERVER_UNREACHABLE,
		FAIL_SERVER_REFUSED,

		REQUEST_CHECK_MACHINE_CONNECTED,
		SUCCESS_MACHINE_CONNECTED,
		FAIL_BAD_SOCKET,
		RETRY_MACHINE_DOWN,
		SUCCESS_DESKTOP_ALREADY_OPEN,

		REQUEST_ASK_MACHINE,
		SUCCESS_ASKED_MACHINE,
		RETRY_ASK_MACHINE,

		REQUEST_ENABLE_REMOTE_DESKTOP,
		SUCCESS_REMOTE_DESKTOP_ENABLED,
		RETRY_REMOTE_DESKTOP_DISABLED,

		REQUEST_CONNECT_LOCAL_RDP,
		SUCCESS_LOCAL_RDP_CONNECTED,
		RETRY_LOCAL_RDP_REFUSED,

		REQUEST_MACHINE_JOIN_RELAY,
		SUCCESS_MACHINE_JOINED_RELAY,
		RETRY_SECOND_CONNECTION,
		RETRY_MACHINE_JOIN_REFUSED,

		REQUEST_MACHINE_STREAM_DATA,
		SUCCESS_MACHINE_STREAMING,
		RETRY_MACHINE_STREAM,
		FAIL_READY_EARLY,

		REQUEST_SERVER_AWAIT_VIEW,
		SUCCESS_SERVER_AWAITING_VIEW,
		RETRY_STREAM_FRESH_CUT,

		REQUEST_CONTROLLER_JOIN_RELAY,
		SUCCESS_CONTROLLER_JOINED_RELAY,
		RETRY_CONTROLLER_JOIN_RELAY,

		SUCCESS_RELAY_FORWARDING,
		RETRY_RELAY_FORWARDING_DROPPED,

		REQUEST_RENDER_DESKTOP,
		SUCCESS_DESKTOP_RENDERED,
		FAIL_PREPARE_RENDER,
		RETRY_RENDER_CONNECT,
		RETRY_DESKTOP_DISCONNECTED,

		SUCCESS_SERVER_RECONNECTED,
		RETRY_SERVER_DISCONNECTED,
		RETRY_SERVER_CONNECT_REFUSED,
		RETRY_CERTIFICATE_RESTORE;

		/**
		 * The sentence for this step.
		 *
		 * @return the text the person sees
		 */
		public string to_string()
		{
			switch (this) {
			case REQUEST_TAKE_CONTROL:
				return "Take control.";
			case SUCCESS_TAKE_CONTROL:
				return "Take control.";
			case FAIL_NO_MACHINE:
				return "No machine is selected.";
			case REQUEST_START_DESKTOP:
				return "Telling the server to open the desktop.";
			case SUCCESS_START_DESKTOP:
				return "Told the server this controller wants to take control.";
			case RETRY_SERVER_UNREACHABLE:
				return "The server cannot be reached.";
			case FAIL_SERVER_REFUSED:
				return "The server refused.";
			case REQUEST_CHECK_MACHINE_CONNECTED:
				return "Checking that the machine is connected.";
			case SUCCESS_MACHINE_CONNECTED:
				return "The machine is connected.";
			case FAIL_BAD_SOCKET:
				return "The desktop request did not arrive on the server's machine socket.";
			case RETRY_MACHINE_DOWN:
				return "The machine is not connected.";
			case SUCCESS_DESKTOP_ALREADY_OPEN:
				return "The desktop is already open.";
			case REQUEST_ASK_MACHINE:
				return "Asking the machine to open Remote Desktop.";
			case SUCCESS_ASKED_MACHINE:
				return "Asked the machine to open Remote Desktop.";
			case RETRY_ASK_MACHINE:
				return "Could not tell the machine.";
			case REQUEST_ENABLE_REMOTE_DESKTOP:
				return "Turning Remote Desktop on.";
			case SUCCESS_REMOTE_DESKTOP_ENABLED:
				return "Remote Desktop is on.";
			case RETRY_REMOTE_DESKTOP_DISABLED:
				return "Waiting for Remote Desktop to be turned on.";
			case REQUEST_CONNECT_LOCAL_RDP:
				return "Connecting to Windows Remote Desktop on the machine.";
			case SUCCESS_LOCAL_RDP_CONNECTED:
				return "The machine started the Remote Desktop connection.";
			case RETRY_LOCAL_RDP_REFUSED:
				return "Windows Remote Desktop refused the connection.";
			case REQUEST_MACHINE_JOIN_RELAY:
				return "The machine is joining the server.";
			case SUCCESS_MACHINE_JOINED_RELAY:
				return "The machine joined the server.";
			case RETRY_SECOND_CONNECTION:
				return "The machine could not open its second connection.";
			case RETRY_MACHINE_JOIN_REFUSED:
				return "The server did not accept the machine.";
			case REQUEST_MACHINE_STREAM_DATA:
				return "The machine is about to send the desktop.";
			case SUCCESS_MACHINE_STREAMING:
				return "The machine is sending the desktop to the server.";
			case RETRY_MACHINE_STREAM:
				return "The machine could not send the desktop.";
			case FAIL_READY_EARLY:
				return "The machine was ready before the screen was open.";
			case REQUEST_SERVER_AWAIT_VIEW:
				return "The server is waiting for this controller.";
			case SUCCESS_SERVER_AWAITING_VIEW:
				return "The server is holding the desktop until this controller joins.";
			case RETRY_STREAM_FRESH_CUT:
				return "Starting the desktop again from the first byte failed.";
			case REQUEST_CONTROLLER_JOIN_RELAY:
				return "This controller is joining the desktop.";
			case SUCCESS_CONTROLLER_JOINED_RELAY:
				return "This controller joined the desktop.";
			case RETRY_CONTROLLER_JOIN_RELAY:
				return "This controller could not join the desktop.";
			case SUCCESS_RELAY_FORWARDING:
				return "The desktop data is coming through.";
			case RETRY_RELAY_FORWARDING_DROPPED:
				return "The desktop connection dropped.";
			case REQUEST_RENDER_DESKTOP:
				return "Drawing the desktop in this window.";
			case SUCCESS_DESKTOP_RENDERED:
				return "The desktop is on screen.";
			case FAIL_PREPARE_RENDER:
				return "The desktop could not be prepared.";
			case RETRY_RENDER_CONNECT:
				return "FreeRDP could not open the desktop.";
			case RETRY_DESKTOP_DISCONNECTED:
				return "The desktop stopped.";
			case SUCCESS_SERVER_RECONNECTED:
				return "Connected to the server again.";
			case RETRY_SERVER_DISCONNECTED:
				return "Disconnected from the server.";
			case RETRY_SERVER_CONNECT_REFUSED:
				return "Could not reach the server.";
			case RETRY_CERTIFICATE_RESTORE:
				return "The machine certificate is missing.";
			default:
				return "";
			}
		}

		/**
		 * The sentence, plus the attempt when this is a retry.
		 *
		 * Attempt ''0'' is the first time. Attempt ''1'' is
		 * "Trying 1 of 3".
		 *
		 * @param attempt how many times this step has been tried after the first
		 * @return {@link to_string}, with the attempt suffix when ''attempt'' is above zero
		 */
		public string line(int attempt)
		{
			var text = this.to_string();
			if (attempt < 1) {
				return text;
			}
			return text + " Trying " + attempt.to_string() + " of 3";
		}
	}
}
