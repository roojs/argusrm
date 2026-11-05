/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 */

namespace SQ
{
	/**
	 * Required contract for rows stored with ''SQ.Query''.
	 */
	public interface Interface : GLib.Object
	{
		public virtual string autoincrement_column()
		{
			return "id";
		}

		/**
		 * Copy writable properties from another row.
		 *
		 * Property names in ''except'' use their GObject form, with dashes
		 * rather than underscores.
		 *
		 * @param source row whose properties are copied
		 * @param except property names that remain unchanged
		 */
		public virtual void copy_from(GLib.Object source, string[] except)
		{
			var target = (GLib.Object) this;
			unowned var target_class = target.get_class();
			foreach (var pspec in source.get_class().list_properties()) {
				if (GLib.strv_contains(except, pspec.name)) {
					continue;
				}
				if ((pspec.flags & GLib.ParamFlags.WRITABLE) == 0 ||
					(pspec.flags & GLib.ParamFlags.CONSTRUCT_ONLY) != 0) {
					continue;
				}
				var target_pspec = target_class.find_property(pspec.name);
				if (target_pspec == null || target_pspec.value_type != pspec.value_type ||
					(target_pspec.flags & GLib.ParamFlags.WRITABLE) == 0) {
					continue;
				}
				var value = GLib.Value(pspec.value_type);
				source.get_property(pspec.name, ref value);
				target.set_property(pspec.name, value);
			}
		}
	}
}
