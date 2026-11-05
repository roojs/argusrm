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

namespace Argus.Server.SQT
{
	/**
	 * One-shot wake-up timer for due tasks.
	 *
	 * The timer is armed for the next schedule. Database reads and
	 * {@link Task.run} stay on the main context, where the server sockets
	 * are owned. {@link reschedule} replaces the timer after a task schedule
	 * or approval changes.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var scheduler = new Argus.Server.SQT.Scheduler(app);
	 * scheduler.start();
	 * }}}
	 */
	public class Scheduler : GLib.Object
	{
		/**
		 * Server that owns the database and main context.
		 */
		public Application app { get; private set; }

		private bool running = false;
		private uint source_id = 0;

		/**
		 * Create the scheduler for one server.
		 *
		 * @param app the running server
		 */
		public Scheduler(Application app)
		{
			Object();
			this.app = app;
		}

		/**
		 * Start the scheduler and arm its first timer.
		 */
		public void start()
		{
			if (this.running) {
				return;
			}
			this.running = true;
			this.reschedule();
		}

		/**
		 * Replace the timer after a task schedule or approval changes.
		 *
		 * Due tasks are dispatched immediately. The next future task then
		 * owns the only scheduler timeout.
		 */
		public void reschedule()
		{
			if (!this.running) {
				return;
			}
			if (this.source_id != 0) {
				GLib.Source.remove(this.source_id);
				this.source_id = 0;
			}
			this.dispatch_due();
			this.arm_next();
		}

		/**
		 * Dispatch every schedule that is due now.
		 */
		private void dispatch_due()
		{
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			Argus.Shared.SQT.Task.query(this.app.db).select(
				"WHERE is_template = 0 AND is_draft = 0 AND completed = 0", tasks);
			var task_rows = new Gee.HashMap<int, Argus.Shared.SQT.Task>();
			foreach (var task in tasks) {
				task_rows.set((int) task.id, task);
			}
			var targets = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			Argus.Shared.SQT.TaskTarget.query(this.app.db).select(
				"WHERE started = 0 AND ended = 0 AND is_cancelled = 0", targets);
			var now = new GLib.DateTime.now_utc().to_unix();
			var task_ids = new Gee.HashMap<int, bool>();
			foreach (var target in targets) {
				if (!task_rows.has_key((int) target.task_id)) {
					continue;
				}
				var task = task_rows.get((int) target.task_id);
				var scheduled = task.scheduled > target.scheduled ?
					task.scheduled : target.scheduled;
				if (scheduled > now || task_ids.has_key((int) target.task_id)) {
					continue;
				}
				task_ids.set((int) target.task_id, true);
				new Task.for_rpc(this.app).run((int) target.task_id);
			}
		}

		/**
		 * Arm a one-shot timeout for the earliest future schedule.
		 */
		private void arm_next()
		{
			var tasks = new Gee.ArrayList<Argus.Shared.SQT.Task>();
			Argus.Shared.SQT.Task.query(this.app.db).select(
				"WHERE is_template = 0 AND is_draft = 0 AND completed = 0", tasks);
			var task_rows = new Gee.HashMap<int, Argus.Shared.SQT.Task>();
			foreach (var task in tasks) {
				task_rows.set((int) task.id, task);
			}
			var targets = new Gee.ArrayList<Argus.Shared.SQT.TaskTarget>();
			Argus.Shared.SQT.TaskTarget.query(this.app.db).select(
				"WHERE started = 0 AND ended = 0 AND is_cancelled = 0", targets);
			var now = new GLib.DateTime.now_utc().to_unix();
			var next = (int64) (-1);
			foreach (var target in targets) {
				if (!task_rows.has_key((int) target.task_id)) {
					continue;
				}
				var task = task_rows.get((int) target.task_id);
				var scheduled = task.scheduled > target.scheduled ?
					task.scheduled : target.scheduled;
				if (scheduled <= now || (next >= 0 && scheduled >= next)) {
					continue;
				}
				next = scheduled;
			}
			if (next < 0) {
				return;
			}
			var delay = next - now;
			var seconds = delay > (int64) uint.MAX ? uint.MAX : (uint) delay;
			this.source_id = GLib.Timeout.add_seconds(seconds, () => {
				this.source_id = 0;
				this.dispatch_due();
				this.arm_next();
				return false;
			});
		}

		/**
		 * Stop the scheduler and cancel its timer.
		 */
		public void stop()
		{
			this.running = false;
			if (this.source_id != 0) {
				GLib.Source.remove(this.source_id);
				this.source_id = 0;
			}
		}
	}
}
