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
 * Controller for Argus.
 *
 * With no command on a desktop, {@link Bootstrap} checks saved
 * connections and may open {@link Window}. {@link Application}
 * hellos on the Unix socket, then runs {@link Pin}, {@link Agents},
 * or {@link Command}. ''--agents'' prints ''id'' and
 * ''requester''. ''--agent'' and ''--command'' run a line on
 * that machine.
 *
 * == Example ==
 *
 * {{{
 * var app = new Argus.Controller.Application();
 * return app.run(args);
 * }}}
 */
namespace Argus.Controller
{
	internal class NamespaceDoc {}
}
