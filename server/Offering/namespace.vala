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
 * Registration desk: TLS listener, registration-port firewall, and
 * mDNS PairPublish for {@link Argus.Server.Offering.Network}.
 *
 * {@link Argus.Server.Offering.Rpc} is the only entry for registration
 * RPC. New code uses {@link Network} and Rpc — not
 * ''Application.register_listen'', ''Application.publish'', or
 * ''Agent.offer''.
 */
namespace Argus.Server.Offering
{
}