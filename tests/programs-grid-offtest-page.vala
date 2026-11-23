/*
 * Same grid wiring as controller/tab/Asset/Programs.vala — real Tab.Base,
 * programs.csv columns, Filters.Programs, FilterListModel, column_grid.
 */

public class ProgramsGridProbePage : Argus.Controller.Tab.Base
{
	public ProgramsGridStore fleet_store { get; private set; }
	private Argus.Controller.Filters.Programs filter;

	public ProgramsGridProbePage(ProgramsGridStore store)
	{
		base("programs", "name");
		this.fleet_store = store;
		this.filter = new Argus.Controller.Filters.Programs();
		var rows = new Gtk.FilterListModel(store, this.filter) {
			incremental = true
		};
		this.column_grid(rows);
		this.content.append(this.overlay);
		this.hexpand = true;
		this.vexpand = true;
	}

	public Gtk.SortListModel? sorted_model()
	{
		GLib.ListModel model = this.grid.model as GLib.ListModel;
		if (model == null) {
			return null;
		}
		if (model is Gtk.SingleSelection) {
			model = ((Gtk.SingleSelection) model).model;
		}
		while (model is Gtk.FilterListModel) {
			model = ((Gtk.FilterListModel) model).model;
		}
		if (model is Gtk.SortListModel) {
			return (Gtk.SortListModel) model;
		}
		return null;
	}

	public Gtk.ScrolledWindow scrolled_window()
	{
		return (Gtk.ScrolledWindow) this.overlay.get_first_child();
	}

	public void tune_sort(bool incremental, bool defer_sorter)
	{
		var sorted = this.sorted_model();
		if (sorted == null) {
			return;
		}
		sorted.incremental = incremental;
		if (defer_sorter) {
			sorted.sorter = null;
		} else {
			sorted.sorter = this.grid.sorter;
		}
	}

	public void attach_sorter()
	{
		var sorted = this.sorted_model();
		if (sorted == null) {
			return;
		}
		sorted.sorter = this.grid.sorter;
	}

	public void freeze_sort_while_busy(bool frozen)
	{
		var sorted = this.sorted_model();
		if (sorted == null) {
			return;
		}
		sorted.sorter = frozen ? null : this.grid.sorter;
	}
}