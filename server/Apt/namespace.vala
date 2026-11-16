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
 * Server-side Debian repository catalog.
 *
 * {@link CatalogRefresh} calls {@link CatalogImport.run_update} daily.
 * {@link CatalogImport} merges Depends and Pre-Depends into
 * {@link Argus.Shared.SQT.AptPkg} and {@link Argus.Shared.SQT.AptPkgDepends}.
 */
namespace Argus.Server.Apt
{
}