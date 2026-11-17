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
 * Query results that are not stored tables.
 *
 * {@link DistributeMachine} is one machine a distributable can be
 * sent to. {@link PackageMachine} is one machine that has a package
 * name. {@link AptDepends} is one package in a Debian dependency
 * preview. None of these types has a table. The stored rows stay in
 * {@link Argus.Shared.SQT}.
 *
 * == Example ==
 *
 * {{{
 * Argus.Shared.SQV.rpc_register();
 * }}}
 */
namespace Argus.Shared.SQV
{
	/**
	 * Register view row types with the ''OLLMrpc'' bin codec.
	 */
	public static void rpc_register()
	{
		DistributeMachine.rpc_register();
		PackageMachine.rpc_register();
		AptDepends.rpc_register();
	}
}
