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
	 * Progress for one distributable upload.
	 *
	 * The file dialog picks the installer. The bar then shows how much
	 * of that file the server has, the size, and a time estimate.
	 * Cancel tells {@link Argus.Controller.Store.Distributable.cancel_upload}
	 * to drop the partial file.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var dialog = new Argus.Controller.Dialog.Upload(store);
	 * dialog.open(window);
	 * }}}
	 */
	public class Upload : Adw.Dialog
	{
		private Argus.Controller.Store.Distributable store;
		private Gtk.Label name_label;
		private Gtk.ProgressBar bar;
		private Gtk.Label size_label;
		private Gtk.Label eta_label;
		private int64 started = 0;
		/**
		 * True while this dialog is on screen.
		 */
		public bool showing { get; private set; default = false; }

		/**
		 * @param store list that sends the chunks
		 */
		public Upload(Argus.Controller.Store.Distributable store)
		{
			Object(title: "Uploading", content_width: 440, can_close: false);
			this.store = store;
			this.name_label = new Gtk.Label("") {
				xalign = 0,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR
			};
			this.bar = new Gtk.ProgressBar() {
				fraction = 0
			};
			this.size_label = new Gtk.Label("Estimating…") {
				xalign = 0
			};
			this.eta_label = new Gtk.Label("Estimating…") {
				xalign = 0
			};
			var cancel = new Gtk.Button.with_label("Cancel") {
				halign = Gtk.Align.END
			};
			var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12) {
				margin_top = 16,
				margin_bottom = 16,
				margin_start = 16,
				margin_end = 16
			};
			box.append(this.name_label);
			box.append(this.bar);
			box.append(this.size_label);
			box.append(this.eta_label);
			box.append(cancel);
			this.child = box;
			cancel.clicked.connect(() => {
				this.store.cancel_upload();
			});
			this.close_attempt.connect(() => {
				this.store.cancel_upload();
			});
			this.store.upload_progress.connect((sent, total) => {
				if (!this.showing) {
					return;
				}
				if (total > 0) {
					this.bar.fraction = ((double) sent / (double) total).clamp(0, 1);
				}
				var sent_text = GLib.format_size((uint64) sent, GLib.FormatSizeFlags.IEC_UNITS)
					.replace("\xc2\xa0", " ")
					.replace("TiB", "TB")
					.replace("GiB", "GB")
					.replace("MiB", "MB")
					.replace("KiB", "KB")
					.replace(".0 ", " ");
				var total_text = GLib.format_size((uint64) total, GLib.FormatSizeFlags.IEC_UNITS)
					.replace("\xc2\xa0", " ")
					.replace("TiB", "TB")
					.replace("GiB", "GB")
					.replace("MiB", "MB")
					.replace("KiB", "KB")
					.replace(".0 ", " ");
				this.size_label.label = sent_text + " of " + total_text;
				if (sent < 1 || sent >= total) {
					if (sent >= total && total > 0) {
						this.eta_label.label = "Finishing…";
						return;
					}
					this.eta_label.label = "Estimating…";
					return;
				}
				var elapsed = (GLib.get_monotonic_time() - this.started) / 1000000.0;
				if (elapsed < 0.5) {
					this.eta_label.label = "Estimating…";
					return;
				}
				var remain = (int) (((double) (total - sent) * elapsed) / (double) sent);
				if (remain < 2) {
					this.eta_label.label = "Less than a second left";
					return;
				}
				if (remain < 60) {
					this.eta_label.label = remain.to_string() + " seconds left";
					return;
				}
				var minutes = (remain + 30) / 60;
				if (minutes < 60) {
					if (minutes == 1) {
						this.eta_label.label = "1 minute left";
						return;
					}
					this.eta_label.label = minutes.to_string() + " minutes left";
					return;
				}
				var hours = (remain + 1800) / 3600;
				if (hours == 1) {
					this.eta_label.label = "1 hour left";
					return;
				}
				this.eta_label.label = hours.to_string() + " hours left";
			});
			this.store.uploaded.connect((row) => {
				if (row == null) {
					return;
				}
				this.dismiss();
			});
			this.store.upload_cancelled.connect(() => {
				this.dismiss();
			});
			this.store.failed.connect((heading, message) => {
				if (!this.showing) {
					return;
				}
				this.dismiss();
			});
		}

		/**
		 * Ask for a file, then upload it.
		 *
		 * @param parent window that owns the file dialog
		 */
		public void open(Gtk.Window parent)
		{
			if (this.showing || this.store.uploading || this.store.busy) {
				return;
			}
			var chooser = new Gtk.FileDialog() {
				title = "Upload installer",
				modal = true
			};
			chooser.open.begin(parent, null, (obj, res) => {
				try {
					var file = chooser.open.end(res);
					if (file == null) {
						return;
					}
					this.name_label.label = file.get_basename();
					this.bar.fraction = 0;
					this.size_label.label = "Estimating…";
					this.eta_label.label = "Estimating…";
					this.started = GLib.get_monotonic_time();
					this.showing = true;
					this.present(parent);
					this.store.upload(file);
				} catch (GLib.Error e) {
					return;
				}
			});
		}

		/**
		 * Hide the dialog after the upload ends.
		 */
		private void dismiss()
		{
			if (!this.showing) {
				return;
			}
			this.showing = false;
			this.force_close();
		}
	}
}
