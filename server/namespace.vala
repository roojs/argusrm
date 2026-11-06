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
 * Argus, the control server.
 *
 * {@link Application} is the headless process.
 * {@link Initialize.fetch_osquery} fetches the osquery
 * installers before the sockets bind. {@link Agent} signs
 * a certificate while {@link Net.SslListen.pin} is set.
 * {@link GitHub.Release} is the release record that fetch reads.
 * {@link Net.SslListen} is the app
 * socket: bin RPC over TLS, the same listen shape as
 * ''ollmfilesd''. {@link Net.Download} is the other socket. It only
 * accepts an HTTPS GET, and it allows or refuses the client
 * certificate. A transfer on that socket is not the app socket.
 * {@link Command} tells one agent to run a command and stores
 * the output for the controller that asked.
 * {@link SQT.Task} manages tasks, templates, and draft targets.
 * {@link SQT.Scheduler} wakes due tasks on the main context.
 *
 * == Example ==
 *
 * {{{
 * var app = new Argus.Server.Application();
 * app.run(args);
 * }}}
 */
namespace Argus.Server
{
	internal class NamespaceDoc {}
}
