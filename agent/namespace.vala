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
 * {@link Application} is the service process. On Windows the file
 * name chooses which one. ''argus-agent'' is the service, started
 * through {@link Win32.Service}. ''argus-tray'' is the window and
 * the tray, {@link Win32.Tray}. The service starts that process in
 * the signed-in session. The tray writes the number on a local
 * pipe, and the service calls {@link Argus.Shared.Register}.
 * {@link Argus.Shared.Browse} finds the broadcast when this launch
 * is not given a host and a port. {@link Download} fetches the
 * osquery installer. {@link OSQuery.Initialize} installs osquery,
 * and {@link OSQuery.Query} runs ''osqueryi --json'' into
 * {@link Argus.Shared.OSQuery.Row} objects. {@link OSQuery.Initialize}
 * syncs each table to the server. Android compiles its own
 * {@link OSQuery.Initialize}, which does not query.
 * {@link Application.notification} takes a command
 * notification. {@link Command} runs it. Linux, Windows, and
 * Android each compile their own file for that class. The
 * Android file does not spawn. A ''agent.send'' notification
 * writes to that command's stdin.
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
