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
 * Command-line controller for Argus.
 *
 * {@link Application} opens the registration window. It creates
 * the six-digit pin, prints it, and calls ''ClientCert.pair''
 * on the Argus Unix socket. Sixty seconds later it sends an
 * empty pin. That is the ''PairingDialog'' window without a
 * drawing.
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
