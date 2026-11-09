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

namespace Argus.Controller
{
	/**
	 * Run one command on a registered agent.
	 *
	 * {@link run} creates a one-line task, adds {@link Application.agent}
	 * as its target, watches that target, and approves it. The scheduler
	 * sends the line.
	 * Notifications emit {@link stdout}, {@link stderr}, and {@link ended}.
	 * The CLI connects those. A desktop can draw them.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var order = new Argus.Controller.Command(app);
	 * order.stdout.connect((text) => { });
	 * order.run();
	 * }}}
	 */
	public class Command : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public Application app;
		public int64 task_id { get; set; default = 0; }
		public string command { get; set; default = ""; }
		public string[] environment { get; set; default = {}; }
		public string cwd { get; set; default = ""; }

		public signal void stdout(string text);
		public signal void stderr(string text);
		public signal void ended();

		public Command(Application app)
		{
			this.app = app;
		}

		/**
		 * Register the outbound command object.
		 */
		public static void rpc_register()
		{
			OLLMrpc.Bin.register("Argus.Command", typeof(Command));
		}

		/**
		 * Create the one-line task and approve it.
		 */
		public void run()
		{
			var id = (int64) 0;
			if (!int64.try_parse(Application.agent, out id) || id < 1 || id > int32.MAX) {
				this.fail("command needs an agent id");
				return;
			}
			this.command = Application.command;
			this.app.rpc.notification.connect((notification) => {
				if (notification.method == "controller.ended") {
					this.ended();
					return;
				}
				if (notification.args.size < 2) {
					return;
				}
				var text = notification.args.get(1).get_string();
				if (notification.method == "controller.stdout") {
					this.stdout(text);
					return;
				}
				if (notification.method == "controller.stderr") {
					this.stderr(text);
				}
			});
			var row = new Argus.Shared.SQT.Task() {
				command = this.command,
				is_script = false,
				script_id = 0,
				scheduled = new GLib.DateTime.now_utc().to_unix() + 1
			};
			this.app.rpc.call.begin(new OLLMrpc.Request() {
				method = "Task.create",
				args = OLLMrpc.args("o", row)
			}, (obj, res) => {
				this.on_created(id, res);
			});
		}

		/**
		 * Add the agent after the task row exists.
		 *
		 * @param agent_id ''agent.id''
		 * @param res the finished ''Task.create'' call
		 */
		private void on_created(int64 agent_id, GLib.AsyncResult res)
		{
			try {
				var response = this.app.rpc.call.end(res);
				if (response.error != null) {
					this.fail(response.error.message);
					return;
				}
				Argus.Shared.SQT.Task row = null;
				if (response.retval.type().is_a(typeof(Argus.Shared.SQT.Task))) {
					row = (Argus.Shared.SQT.Task) response.retval.get_object();
				}
				if (row == null || row.id < 1) {
					this.fail("invalid task");
					return;
				}
				this.task_id = row.id;
				var agents = new GLib.Variant.array(
					new GLib.VariantType("i"),
					{ new GLib.Variant.int32((int32) agent_id) });
				this.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "Task.target",
					args = OLLMrpc.args("iv", (int) this.task_id, agents)
				}, (obj, target_res) => {
					this.on_targeted(target_res);
				});
			} catch (GLib.Error e) {
				this.fail(e.message);
			}
		}

		/**
		 * Watch the new target, then approve the task.
		 *
		 * @param res the finished ''Task.target'' call
		 */
		private void on_targeted(GLib.AsyncResult res)
		{
			try {
				var response = this.app.rpc.call.end(res);
				if (response.error != null) {
					this.fail(response.error.message);
					return;
				}
				Gee.ArrayList<Argus.Shared.SQT.TaskTarget> targets = null;
				if (response.retval.type().is_a(typeof(Gee.ArrayList))) {
					targets = (Gee.ArrayList<Argus.Shared.SQT.TaskTarget>) response.retval.get_object();
				}
				if (targets == null || targets.size < 1 || targets.get(0).id < 1) {
					this.fail("invalid task");
					return;
				}
				this.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "Task.watch",
					args = OLLMrpc.args("i", (int) targets.get(0).id)
				}, (obj, watch_res) => {
					this.on_watched(watch_res);
				});
			} catch (GLib.Error e) {
				this.fail(e.message);
			}
		}

		/**
		 * Approve the task once its output is being watched.
		 *
		 * @param res the finished ''Task.watch'' call
		 */
		private void on_watched(GLib.AsyncResult res)
		{
			try {
				var response = this.app.rpc.call.end(res);
				if (response.error != null) {
					this.fail(response.error.message);
					return;
				}
				this.app.rpc.call.begin(new OLLMrpc.Request() {
					method = "Task.approve",
					args = OLLMrpc.args("ib", (int) this.task_id, true)
				}, (obj, approve_res) => {
					try {
						var approved = this.app.rpc.call.end(approve_res);
						if (approved.error != null) {
							this.fail(approved.error.message);
						}
					} catch (GLib.Error e) {
						this.fail(e.message);
					}
				});
			} catch (GLib.Error e) {
				this.fail(e.message);
			}
		}

		/**
		 * Print one failure and finish the command.
		 *
		 * @param message text for {@link stderr}
		 */
		private void fail(string message)
		{
			this.stderr(message.has_suffix("\n") ? message : message + "\n");
			this.ended();
		}
	}
}
