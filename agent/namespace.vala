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
 * The program that runs on a managed machine.
 *
 * {@link Application} is the process. On Windows the Service Control
 * Manager starts it through {@link Win32.Service}. Registration is
 * {@link Argus.Shared.Register}. {@link Argus.Shared.Browse} finds
 * the broadcast when this launch is not given a host and a port.
 *
 * == Example ==
 *
 * {{{
 * var app = new Argus.Agent.Application();
 * app.run(args);
 * }}}
 */
namespace Argus.Agent
{
	internal class NamespaceDoc {}
}
