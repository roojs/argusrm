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
 * Detail tabs shown under a selected machine on the Machines page.
 *
 * {@link Detail} switches per-machine tabs below
 * {@link Argus.Controller.Tab.Asset.SystemInfo}. Per-machine tabs load
 * {@link General}, {@link Users}, {@link Groups}, {@link DebPackages},
 * {@link RpmPackages}, {@link Programs}, and {@link InterfaceAddresses}
 * for the selected machine's ''agent_id''.
 *
 * == Example ==
 *
 * {{{
 * var detail = new Argus.Controller.Tab.Asset.Machine.Detail(window);
 * detail.show_machine(machine);
 * }}}
 */
namespace Argus.Controller.Tab.Asset.Machine
{
	internal class NamespaceDoc {}
}
