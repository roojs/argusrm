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

namespace Argus.Controller.Widget
{
	/**
	 * Reusable press-and-hold confirmation button.
	 *
	 * Renders a neutral flat button in its inactive state, defaulting to a
	 * trash icon. Pressing and holding switches to an active red state with
	 * a countdown progress bar along the bottom for {@link duration}
	 * milliseconds, then emits {@link confirmed}. Releasing early emits
	 * {@link short_click}. Moving the pointer off cancels the hold.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var button = new Argus.Controller.Widget.HoldButton();
	 * button.short_click.connect(() => {
	 *     toasts.add_toast(new Adw.Toast("Click and hold to remove"));
	 * });
	 * button.confirmed.connect(() => {
	 *     this.remove_selected();
	 * });
	 * }}}
	 */
	public class HoldButton : Gtk.Box
	{
		/**
		 * Icon name shown inside the button.
		 */
		public string icon_name { get; set; default = "user-trash-symbolic"; }

		/**
		 * Optional label shown beside the icon. Empty hides the label.
		 */
		public string label { get; set; default = ""; }

		/**
		 * Hold time in milliseconds before {@link confirmed} fires.
		 */
		public int duration { get; set; default = 2000; }

		/**
		 * True while the button is actively held and animating.
		 */
		public bool holding { get; private set; default = false; }

		private bool finished = false;
		private int64 started = 0;
		private Gtk.Button button;
		private Gtk.ProgressBar bar;
		private Adw.TimedAnimation animation;

		/**
		 * Emitted when the button is released before {@link duration}
		 * elapses.
		 */
		public signal void short_click();

		/**
		 * Emitted after the button is held for the full {@link duration}.
		 */
		public signal void confirmed();

		/**
		 * Create a press-and-hold button defaulting to a trash icon.
		 */
		public HoldButton()
		{
			Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
			this.overflow = Gtk.Overflow.HIDDEN;
			this.add_css_class("hold-button");
			var image = new Gtk.Image() {
				icon_name = this.icon_name
			};
			var text = new Gtk.Label(this.label) {
				visible = this.label != ""
			};
			var content = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.CENTER
			};
			content.append(image);
			content.append(text);
			this.button = new Gtk.Button() {
				child = content,
				hexpand = true,
				vexpand = true,
				focus_on_click = false,
				css_classes = { "flat" }
			};
			this.bind_property("icon-name", image, "icon-name", GLib.BindingFlags.SYNC_CREATE);
			this.bind_property("label", text, "label", GLib.BindingFlags.SYNC_CREATE);
			this.notify["label"].connect(() => {
				text.visible = this.label != "";
			});
			this.bar = new Gtk.ProgressBar() {
				valign = Gtk.Align.END,
				hexpand = true,
				fraction = 0,
				visible = false,
				can_target = false,
				css_classes = { "hold-bar" }
			};
			var overlay = new Gtk.Overlay() {
				child = this.button,
				hexpand = true,
				vexpand = true
			};
			overlay.add_overlay(this.bar);
			this.append(overlay);
			var countdown = new Adw.CallbackAnimationTarget((value) => {
				this.bar.fraction = value;
			});
			this.animation = new Adw.TimedAnimation(
				this, 1, 0, this.duration, countdown) {
				easing = Adw.Easing.LINEAR,
				follow_enable_animations_setting = false
			};
			this.notify["duration"].connect(() => {
				this.animation.duration = this.duration;
			});
			this.animation.done.connect(() => {
				if (!this.holding) {
					return;
				}
				/* A skipped animation finishes at once. */
				if (GLib.get_monotonic_time() - this.started < (int64) this.duration * 900) {
					this.reset();
					return;
				}
				this.reset();
				this.finished = true;
				this.confirmed();
			});
			var hold = new Gtk.EventControllerLegacy() {
				propagation_phase = Gtk.PropagationPhase.CAPTURE
			};
			hold.event.connect((event) => {
				var start = false;
				var stop = false;
				var cancelled = false;
				switch (event.get_event_type()) {
					case Gdk.EventType.BUTTON_PRESS:
						if (event.triggers_context_menu() ||
							((Gdk.ButtonEvent) event).get_button() != Gdk.BUTTON_PRIMARY) {
							return false;
						}
						start = true;
						break;

					case Gdk.EventType.TOUCH_BEGIN:
						start = true;
						break;

					case Gdk.EventType.BUTTON_RELEASE:
						if (((Gdk.ButtonEvent) event).get_button() != Gdk.BUTTON_PRIMARY) {
							return false;
						}
						stop = true;
						break;

					case Gdk.EventType.TOUCH_END:
						stop = true;
						break;

					case Gdk.EventType.TOUCH_CANCEL:
						stop = true;
						cancelled = true;
						break;

					default:
						break;
				}
				if (!start && !stop) {
					return false;
				}
				if (start) {
					if (!this.sensitive || this.holding) {
						return true;
					}
					this.finished = false;
					this.holding = true;
					this.started = GLib.get_monotonic_time();
					this.add_css_class("holding");
					this.bar.visible = true;
					this.bar.fraction = 1;
					this.animation.play();
					return true;
				}
				if (this.finished) {
					this.finished = false;
					return true;
				}
				if (!this.holding) {
					return true;
				}
				this.reset();
				if (!cancelled) {
					this.short_click();
				}
				return true;
			});
			var motion = new Gtk.EventControllerMotion();
			motion.leave.connect(() => {
				if (!this.holding) {
					return;
				}
				this.reset();
			});
			this.add_controller(hold);
			this.add_controller(motion);
			this.notify["sensitive"].connect(() => {
				if (!this.sensitive && this.holding) {
					this.reset();
				}
			});
			this.unmap.connect(() => {
				if (this.holding || this.finished) {
					this.reset();
				}
			});
		}

		/**
		 * Cancel any active hold animation and restore the inactive state.
		 */
		public void reset()
		{
			this.holding = false;
			this.finished = false;
			this.animation.reset();
			this.bar.fraction = 0;
			this.bar.visible = false;
			this.remove_css_class("holding");
		}
	}
}
