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
 * Process entry for {@link Argus.Agent.Rdp.Desk}.
 *
 * argv: port certificate.crt private.key
 */
int main(string[] args)
{
	if (args.length != 4) {
		stderr.printf("usage: argus-rdp-desk port certificate key\n");
		return 2;
	}
	int port = int.parse(args[1]);
	if (port < 1 || port > 65535) {
		return 2;
	}
	return new Argus.Agent.Rdp.Desk(args[2], args[3]).run((uint16) port);
}
