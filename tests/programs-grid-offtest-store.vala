/*
 * ListModel for programs grid off-test (same signals as Store.Programs).
 */

public class ProgramsGridStore : GLib.Object, GLib.ListModel
{
	private Gee.ArrayList<Argus.Shared.OSQuery.Programs> items_store =
		new Gee.ArrayList<Argus.Shared.OSQuery.Programs>();

	public bool busy { get; set; default = false; }

	public GLib.Type get_item_type() { return typeof(Argus.Shared.OSQuery.Programs); }

	public uint get_n_items() { return (uint) this.items_store.size; }

	public GLib.Object? get_item(uint position)
	{
		if (position >= (uint) this.items_store.size) {
			return null;
		}
		return this.items_store.get((int) position);
	}

	public void replace_all(Gee.ArrayList<Argus.Shared.OSQuery.Programs> rows)
	{
		var removed = (uint) this.items_store.size;
		this.items_store = rows;
		this.items_changed(0, removed, (uint) rows.size);
	}
}