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


 /// BEWARE - this is unreviewed LLM code - normally we dont allow this - but dealing with 
 /// installer stuff 
namespace Argus.Server.Win
{
	/**
	 * Why an uploaded file was not stored as an installer.
	 */
	public errordomain InstallerError {
		REJECTED
	}

	/**
	 * Name and version read from an NSIS installer.
	 *
	 * {@link Installer.from_file} accepts a PE whose overlay contains
	 * the NSIS first-header signature. It reads ''ProductName'' and
	 * ''ProductVersion'' from the PE version resource when those exist.
	 * Otherwise it reads ''DisplayName'' and ''DisplayVersion'' from the
	 * uncompressed NSIS script, which is where ''Name'' and the uninstall
	 * registry values live when the ''.nsi'' does not set a version resource.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var info = new Argus.Server.Win.Installer.from_file(path);
	 * }}}
	 */
	public class Installer : GLib.Object
	{
		/**
		 * ''ProductName'' from the version resource.
		 */
		public string name { get; private set; default = ""; }
		/**
		 * ''ProductVersion'', or ''FileVersion'' when that is empty.
		 */
		public string version { get; private set; default = ""; }
		/**
		 * Lower-case SHA-256 hex of the file bytes.
		 */
		public string sha256 { get; private set; default = ""; }
		/**
		 * File length in bytes.
		 */
		public int64 size { get; private set; default = 0; }

		/**
		 * Read one installer.
		 *
		 * @param path file to hash and read
		 */
		public Installer.from_file(string path) throws InstallerError
		{
			Object();
			int64 size;
			string sha;
			bool nsis;
			this.scan(path, out size, out sha, out nsis);
			if (!nsis) {
				throw new InstallerError.REJECTED("not an NSIS installer");
			}
			var strings = this.version_strings(path, size);
			var name = (strings.get("ProductName") ?? "").strip();
			var version = (strings.get("ProductVersion") ?? "").strip();
			if (version == "") {
				version = (strings.get("FileVersion") ?? "").strip();
			}
			if (name == "" || version == "") {
				string script_name;
				string script_version;
				if (this.nsis_registry(path, out script_name, out script_version)) {
					if (name == "") {
						name = script_name;
					}
					if (version == "") {
						version = script_version;
					}
				}
			}
			if (name == "") {
				throw new InstallerError.REJECTED("installer has no product name");
			}
			if (version == "") {
				throw new InstallerError.REJECTED("installer has no version");
			}
			this.name = name;
			this.version = version;
			this.sha256 = sha;
			this.size = size;
		}

		/**
		 * Hash the file and look for the NSIS signature.
		 *
		 * The signature is ''0xDEADBEEF'' followed by the three
		 * little-endian ints that spell ''NullsoftInst''.
		 *
		 * @param path file to read
		 * @param size file length
		 * @param sha SHA-256 hex
		 * @param nsis true when the signature is present
		 */
		private void scan(string path, out int64 size, out string sha, out bool nsis) throws InstallerError
		{
			size = 0;
			sha = "";
			nsis = false;
			GLib.FileInputStream input;
			try {
				input = GLib.File.new_for_path(path).read();
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			var sum = new GLib.Checksum(GLib.ChecksumType.SHA256);
			uint8[] sig = {
				0xEF, 0xBE, 0xAD, 0xDE,
				0x4E, 0x75, 0x6C, 0x6C,
				0x73, 0x6F, 0x66, 0x74,
				0x49, 0x6E, 0x73, 0x74
			};
			var prev = new uint8[0];
			var buf = new uint8[64 * 1024];
			try {
				while (true) {
					var n = input.read(buf);
					if (n < 0) {
						throw new InstallerError.REJECTED("could not read the installer");
					}
					if (n == 0) {
						break;
					}
					var chunk = new uint8[n];
					GLib.Memory.copy((uint8*) chunk, buf, n);
					sum.update(chunk, chunk.length);
					size += (int64) n;
					if (nsis) {
						continue;
					}
					var window = new uint8[prev.length + chunk.length];
					if (prev.length > 0) {
						GLib.Memory.copy((uint8*) window, prev, prev.length);
					}
					GLib.Memory.copy((uint8*) window + prev.length, chunk, chunk.length);
					if (window.length >= sig.length) {
						for (var i = 0; i <= window.length - sig.length; i++) {
							var match = true;
							for (var j = 0; j < sig.length; j++) {
								if (window[i + j] != sig[j]) {
									match = false;
									break;
								}
							}
							if (match) {
								nsis = true;
								break;
							}
						}
					}
					var keep = sig.length - 1;
					if (keep > window.length) {
						keep = window.length;
					}
					prev = new uint8[keep];
					if (keep > 0) {
						GLib.Memory.copy((uint8*) prev, (uint8*) window + (window.length - keep), keep);
					}
				}
				input.close();
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			sha = sum.get_string();
		}

		/**
		 * ''ProductName'' and the other version-resource strings.
		 *
		 * An empty map means the PE has no version resource we can read.
		 *
		 * @param path installer path
		 * @param size file length from {@link scan}
		 * @return string keys from the version resource
		 */
		private Gee.HashMap<string, string> version_strings(string path, int64 size) throws InstallerError
		{
			var strings = new Gee.HashMap<string, string>();
			if (size < 0x40) {
				return strings;
			}
			GLib.FileInputStream input;
			try {
				input = GLib.File.new_for_path(path).read();
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			try {
				var dos = read_at(input, 0, 0x40);
				if (dos[0] != (uint8) 'M' || dos[1] != (uint8) 'Z') {
					input.close();
					return strings;
				}
				var e_lfanew = (int64) (
					(uint32) dos[0x3C]
					| ((uint32) dos[0x3D] << 8)
					| ((uint32) dos[0x3E] << 16)
					| ((uint32) dos[0x3F] << 24));
				if (e_lfanew < 0x40 || e_lfanew + 24 > size) {
					input.close();
					return strings;
				}
				var pe = read_at(input, e_lfanew, 24);
				if (pe[0] != (uint8) 'P' || pe[1] != (uint8) 'E' || pe[2] != 0 || pe[3] != 0) {
					input.close();
					return strings;
				}
				var nsections = (int) ((uint16) pe[6] | ((uint16) pe[7] << 8));
				var opt_size = (int) ((uint16) pe[20] | ((uint16) pe[21] << 8));
				if (nsections < 1 || nsections > 96 || opt_size < 96 || opt_size > 4096) {
					input.close();
					return strings;
				}
				if (e_lfanew + 24 + opt_size + (int64) nsections * 40 > size) {
					input.close();
					return strings;
				}
				var opt = read_at(input, e_lfanew + 24, opt_size);
				var magic = (uint16) opt[0] | ((uint16) opt[1] << 8);
				int dd;
				uint32 dd_count;
				if (magic == 0x10B) {
					dd = 96;
					dd_count = (uint32) opt[92]
						| ((uint32) opt[93] << 8)
						| ((uint32) opt[94] << 16)
						| ((uint32) opt[95] << 24);
				} else if (magic == 0x20B) {
					dd = 112;
					dd_count = (uint32) opt[108]
						| ((uint32) opt[109] << 8)
						| ((uint32) opt[110] << 16)
						| ((uint32) opt[111] << 24);
				} else {
					input.close();
					return strings;
				}
				if (dd_count < 3 || dd + 24 > opt.length) {
					input.close();
					return strings;
				}
				var res_rva = (uint32) opt[dd + 16]
					| ((uint32) opt[dd + 17] << 8)
					| ((uint32) opt[dd + 18] << 16)
					| ((uint32) opt[dd + 19] << 24);
				var res_size = (uint32) opt[dd + 20]
					| ((uint32) opt[dd + 21] << 8)
					| ((uint32) opt[dd + 22] << 16)
					| ((uint32) opt[dd + 23] << 24);
				if (res_rva == 0 || res_size < 16 || res_size > 32 * 1024 * 1024) {
					input.close();
					return strings;
				}
				var table = read_at(input, e_lfanew + 24 + opt_size, nsections * 40);
				uint64 res_off = (uint64) int64.MAX;
				for (var i = 0; i < nsections; i++) {
					var o = i * 40;
					var vsz = (uint32) table[o + 8]
						| ((uint32) table[o + 9] << 8)
						| ((uint32) table[o + 10] << 16)
						| ((uint32) table[o + 11] << 24);
					var va = (uint32) table[o + 12]
						| ((uint32) table[o + 13] << 8)
						| ((uint32) table[o + 14] << 16)
						| ((uint32) table[o + 15] << 24);
					var rsz = (uint32) table[o + 16]
						| ((uint32) table[o + 17] << 8)
						| ((uint32) table[o + 18] << 16)
						| ((uint32) table[o + 19] << 24);
					var raw = (uint32) table[o + 20]
						| ((uint32) table[o + 21] << 8)
						| ((uint32) table[o + 22] << 16)
						| ((uint32) table[o + 23] << 24);
					var span = vsz > rsz ? vsz : rsz;
					if (span > 0 && res_rva >= va && res_rva < va + span) {
						res_off = (uint64) raw + (uint64) (res_rva - va);
						break;
					}
				}
				if (res_off > (uint64) size || (uint64) res_size > (uint64) size ||
					res_off + (uint64) res_size > (uint64) size) {
					input.close();
					return strings;
				}
				var blob = read_at(input, (int64) res_off, (int) res_size);
				input.close();
				var ver = this.walk_resource(blob, 0, 0, res_rva);
				if (ver != null) {
					this.collect_strings(ver, 0, ver.length, strings);
				}
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			return strings;
		}

		/**
		 * Depth 0 keeps resource type 16. The leaf is the version bytes.
		 *
		 * @param blob resource section
		 * @param dir offset of this directory
		 * @param depth 0 is the root
		 * @param res_rva RVA of ''blob''[0]
		 * @return version bytes, or null
		 */
		private uint8[]? walk_resource(uint8[] blob, int dir, int depth, uint32 res_rva)
		{
			if (depth > 3 || dir < 0 || dir + 16 > blob.length) {
				return null;
			}
			var named = (int) ((uint16) blob[dir + 12] | ((uint16) blob[dir + 13] << 8));
			var ids = (int) ((uint16) blob[dir + 14] | ((uint16) blob[dir + 15] << 8));
			var count = named + ids;
			if (count < 0 || count > 4096 || dir + 16 + count * 8 > blob.length) {
				return null;
			}
			for (var i = 0; i < count; i++) {
				var eo = dir + 16 + i * 8;
				var name = (uint32) blob[eo]
					| ((uint32) blob[eo + 1] << 8)
					| ((uint32) blob[eo + 2] << 16)
					| ((uint32) blob[eo + 3] << 24);
				var off = (uint32) blob[eo + 4]
					| ((uint32) blob[eo + 5] << 8)
					| ((uint32) blob[eo + 6] << 16)
					| ((uint32) blob[eo + 7] << 24);
				var high = (uint32) 1 << 31;
				if (depth == 0 && ((name & high) != 0 || name != 16)) {
					continue;
				}
				var child = (int) (off & ~high);
				if ((off & high) != 0) {
					var hit = this.walk_resource(blob, child, depth + 1, res_rva);
					if (hit != null) {
						return hit;
					}
					continue;
				}
				if (child < 0 || child + 8 > blob.length) {
					continue;
				}
				var data_rva = (uint32) blob[child]
					| ((uint32) blob[child + 1] << 8)
					| ((uint32) blob[child + 2] << 16)
					| ((uint32) blob[child + 3] << 24);
				var data_size = (uint32) blob[child + 4]
					| ((uint32) blob[child + 5] << 8)
					| ((uint32) blob[child + 6] << 16)
					| ((uint32) blob[child + 7] << 24);
				if (data_size < 6 || data_size > 1024 * 1024 || data_rva < res_rva) {
					continue;
				}
				var index = (int) (data_rva - res_rva);
				if (index < 0 || (int64) index + data_size > blob.length) {
					continue;
				}
				var slice = new uint8[data_size];
				GLib.Memory.copy((uint8*) slice, (uint8*) blob + index, data_size);
				return slice;
			}
			return null;
		}

		/**
		 * Walk a ''VS_VERSIONINFO'' tree and keep each text value.
		 *
		 * @param blob version resource
		 * @param o start of this block
		 * @param end end of the parent block
		 * @param strings key to value
		 */
		private void collect_strings(uint8[] blob, int o, int end, Gee.HashMap<string, string> strings)
		{
			if (o < 0 || o + 6 > end || o + 6 > blob.length) {
				return;
			}
			var length = (int) ((uint16) blob[o] | ((uint16) blob[o + 1] << 8));
			var vlen = (int) ((uint16) blob[o + 2] | ((uint16) blob[o + 3] << 8));
			var typ = (uint16) blob[o + 4] | ((uint16) blob[o + 5] << 8);
			if (length < 6) {
				return;
			}
			var block_end = o + length;
			if (block_end > end) {
				block_end = end;
			}
			if (block_end > blob.length) {
				block_end = blob.length;
			}
			var p = o + 6;
			var key_chars = new GLib.StringBuilder();
			while (p + 1 < block_end && p + 1 < blob.length && key_chars.len < 512) {
				uint16 c = (uint16) blob[p] | ((uint16) blob[p + 1] << 8);
				p += 2;
				if (c == 0) {
					break;
				}
				key_chars.append_unichar((unichar) c);
			}
			var key = key_chars.str;
			p = (p + 3) & ~3;
			if (typ == 1 && vlen > 0) {
				var nbytes = vlen * 2;
				if (p > blob.length) {
					nbytes = 0;
				} else if (p + nbytes > blob.length) {
					nbytes = blob.length - p;
				}
				if (key != "" && nbytes > 0) {
					var val_chars = new GLib.StringBuilder();
					var i = 0;
					while (i + 1 < nbytes && p + i + 1 < blob.length && val_chars.len < 512) {
						uint16 c = (uint16) blob[p + i] | ((uint16) blob[p + i + 1] << 8);
						i += 2;
						if (c == 0) {
							break;
						}
						val_chars.append_unichar((unichar) c);
					}
					strings.set(key, val_chars.str.strip());
				}
				p = (p + vlen * 2 + 3) & ~3;
			} else if (vlen > 0) {
				p = (p + vlen + 3) & ~3;
			}
			while (p + 6 <= block_end && p + 6 <= blob.length) {
				var child_len = (int) ((uint16) blob[p] | ((uint16) blob[p + 1] << 8));
				if (child_len < 6) {
					return;
				}
				var next = (p + child_len + 3) & ~3;
				this.collect_strings(blob, p, block_end, strings);
				if (next <= p) {
					return;
				}
				p = next;
			}
		}

		/**
		 * ''DisplayName'' and ''DisplayVersion'' from a deflate NSIS script.
		 *
		 * The script is the compressed block after the first header.
		 * A non-solid deflate block starts with a 4-byte marker whose
		 * last byte is ''0x80''. String positions in the instructions
		 * are character offsets into the string block. A ''WriteReg''
		 * whose value name is ''DisplayName'' or ''DisplayVersion''
		 * supplies the text. The uninstall key wins when more than one
		 * write uses that name.
		 *
		 * @param path installer path
		 * @param name product name, or empty
		 * @param version product version, or empty
		 * @return true when the script yielded a name or a version
		 */
		private bool nsis_registry(string path, out string name, out string version) throws InstallerError
		{
			name = "";
			version = "";
			GLib.FileInputStream input;
			try {
				input = GLib.File.new_for_path(path).read();
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			uint8[] sig = {
				0xEF, 0xBE, 0xAD, 0xDE,
				0x4E, 0x75, 0x6C, 0x6C,
				0x73, 0x6F, 0x66, 0x74,
				0x49, 0x6E, 0x73, 0x74
			};
			var prev = new uint8[0];
			var buf = new uint8[64 * 1024];
			int64 pos =  0;
			int64 sig_at = -1;
			try {
				while (sig_at < 0) {
					var n = input.read(buf);
					if (n <= 0) {
						break;
					}
					var chunk = new uint8[n];
					GLib.Memory.copy((uint8*) chunk, buf, n);
					var window = new uint8[prev.length + chunk.length];
					if (prev.length > 0) {
						GLib.Memory.copy((uint8*) window, prev, prev.length);
					}
					GLib.Memory.copy((uint8*) window + prev.length, chunk, chunk.length);
					if (window.length >= sig.length) {
						for (var i = 0; i <= window.length - sig.length; i++) {
							var match = true;
							for (var j = 0; j < sig.length; j++) {
								if (window[i + j] != sig[j]) {
									match = false;
									break;
								}
							}
							if (!match) {
								continue;
							}
							sig_at = pos + chunk.length - window.length + i;
							break;
						}
					}
					var keep = sig.length - 1;
					if (keep > window.length) {
						keep = window.length;
					}
					prev = new uint8[keep];
					if (keep > 0) {
						GLib.Memory.copy((uint8*) prev,
							(uint8*) window + (window.length - keep), keep);
					}
					pos += (int64) n;
				}
			} catch (GLib.Error e) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			if (sig_at < 4) {
				return false;
			}
			uint8[] head;
			try {
				head = this.read_at(input, sig_at - 4, 28);
			} catch (GLib.Error e) {
				return false;
			}
			var compressed = (int) (
				(uint32) head[20]
				| ((uint32) head[21] << 8)
				| ((uint32) head[22] << 16)
				| ((uint32) head[23] << 24));
			if (compressed < 16 || compressed > 8 * 1024 * 1024) {
				return false;
			}
			uint8[] payload;
			try {
				payload = this.read_at(input, sig_at - 4 + 28, compressed);
			} catch (GLib.Error e) {
				return false;
			}
			try {
				input.close();
			} catch (GLib.Error e) {
				return false;
			}
			var comp = payload;
			if (payload.length > 8 && payload[3] == 0x80) {
				if (payload[4] == 0x5D || payload[4] == 0x31) {
					return false;
				}
				comp = new uint8[payload.length - 4];
				GLib.Memory.copy((uint8*) comp, (uint8*) payload + 4, comp.length);
			}
			var header = new uint8[0];
			try {
				var source = new GLib.MemoryInputStream.from_data(comp);
				var decoded = new GLib.ConverterInputStream(source,
					new GLib.ZlibDecompressor(GLib.ZlibCompressorFormat.RAW));
				var outbuf = new uint8[64 * 1024];
				header = new uint8[64 * 1024];
				var total = 0;
				while (total < 8 * 1024 * 1024) {
					var n = decoded.read(outbuf);
					if (n <= 0) {
						break;
					}
					if (total + (int) n > header.length) {
						var bigger = new uint8[header.length * 2];
						GLib.Memory.copy((uint8*) bigger, header, total);
						header = bigger;
					}
					GLib.Memory.copy((uint8*) header + total, outbuf, n);
					total += (int) n;
				}
				var body = new uint8[total];
				if (total > 0) {
					GLib.Memory.copy((uint8*) body, header, total);
				}
				header = body;
			} catch (GLib.Error e) {
				return false;
			}
			if (header.length >= 8) {
				var mark = (uint32) header[0]
					| ((uint32) header[1] << 8)
					| ((uint32) header[2] << 16)
					| ((uint32) header[3] << 24);
				if (mark == (uint32) compressed && header.length >= 4 + compressed) {
					var body = new uint8[compressed];
					GLib.Memory.copy((uint8*) body, (uint8*) header + 4, compressed);
					header = body;
				}
			}
			var entries_at = -1;
			var entries_n = 0;
			var strings_at = 0;
			var strings_end = 0;
			int[] widths = { 12, 8 };
			foreach (var width in widths) {
				if (4 + 8 * width > header.length) {
					continue;
				}
				for (var i = 0; i < 7; i++) {
					var o = 4 + i * width;
					uint64 off;
					uint32 num;
					uint64 next;
					if (width == 12) {
						off = (uint64) header[o]
							| ((uint64) header[o + 1] << 8)
							| ((uint64) header[o + 2] << 16)
							| ((uint64) header[o + 3] << 24)
							| ((uint64) header[o + 4] << 32)
							| ((uint64) header[o + 5] << 40)
							| ((uint64) header[o + 6] << 48)
							| ((uint64) header[o + 7] << 56);
						num = (uint32) header[o + 8]
							| ((uint32) header[o + 9] << 8)
							| ((uint32) header[o + 10] << 16)
							| ((uint32) header[o + 11] << 24);
						var n = o + width;
						next = (uint64) header[n]
							| ((uint64) header[n + 1] << 8)
							| ((uint64) header[n + 2] << 16)
							| ((uint64) header[n + 3] << 24)
							| ((uint64) header[n + 4] << 32)
							| ((uint64) header[n + 5] << 40)
							| ((uint64) header[n + 6] << 48)
							| ((uint64) header[n + 7] << 56);
					} else {
						off = (uint32) header[o]
							| ((uint32) header[o + 1] << 8)
							| ((uint32) header[o + 2] << 16)
							| ((uint32) header[o + 3] << 24);
						num = (uint32) header[o + 4]
							| ((uint32) header[o + 5] << 8)
							| ((uint32) header[o + 6] << 16)
							| ((uint32) header[o + 7] << 24);
						var n = o + width;
						next = (uint32) header[n]
							| ((uint32) header[n + 1] << 8)
							| ((uint32) header[n + 2] << 16)
							| ((uint32) header[n + 3] << 24);
					}
					if (num < 1 || num > 200000 || next <= off) {
						continue;
					}
					if (off + (uint64) num * 28 != next || next >= (uint64) header.length) {
						continue;
					}
					entries_at = (int) off;
					entries_n = (int) num;
					strings_at = (int) next;
					strings_end = header.length;
					if (i < 6) {
						var n3 = o + width * 2;
						uint64 after;
						if (width == 12) {
							after = (uint64) header[n3]
								| ((uint64) header[n3 + 1] << 8)
								| ((uint64) header[n3 + 2] << 16)
								| ((uint64) header[n3 + 3] << 24)
								| ((uint64) header[n3 + 4] << 32)
								| ((uint64) header[n3 + 5] << 40)
								| ((uint64) header[n3 + 6] << 48)
								| ((uint64) header[n3 + 7] << 56);
						} else {
							after = (uint32) header[n3]
								| ((uint32) header[n3 + 1] << 8)
								| ((uint32) header[n3 + 2] << 16)
								| ((uint32) header[n3 + 3] << 24);
						}
						if (after > next && after <= (uint64) header.length) {
							strings_end = (int) after;
						}
					}
					break;
				}
				if (entries_at >= 0) {
					break;
				}
			}
			if (entries_at < 0) {
				return false;
			}
			var chosen_name = "";
			var chosen_version = "";
			var other_name = "";
			var other_version = "";
			for (var i = 0; i < entries_n; i++) {
				var o = entries_at + i * 28;
				if (o + 28 > header.length) {
					break;
				}
				int[] field = new int[5];
				for (var f = 0; f < 5; f++) {
					var p = o + 4 + f * 4;
					field[f] = (int) (
						(uint32) header[p]
						| ((uint32) header[p + 1] << 8)
						| ((uint32) header[p + 2] << 16)
						| ((uint32) header[p + 3] << 24));
				}
				if (field[4] != 1) {
					continue;
				}
				string[] text = new string[3];
				for (var f = 1; f < 4; f++) {
					var chars = new GLib.StringBuilder();
					var p = strings_at + field[f] * 2;
					if (field[f] < 0 || p < strings_at || p >= strings_end) {
						text[f - 1] = "";
						continue;
					}
					while (p + 1 < strings_end && chars.len < 200) {
						uint16 c = (uint16) header[p] | ((uint16) header[p + 1] << 8);
						p += 2;
						if (c == 0) {
							break;
						}
						if (c < 32 || c > 126) {
							chars.erase(0, -1);
							break;
						}
						chars.append_unichar((unichar) c);
					}
					text[f - 1] = chars.str;
				}
				var key = text[0];
				var item = text[1];
				var data = text[2].strip();
				if (data == "") {
					continue;
				}
				var uninstall = key.down().contains("uninstall");
				if (item == "DisplayName") {
					if (uninstall || other_name == "") {
						other_name = data;
					}
					if (uninstall) {
						chosen_name = data;
					}
				}
				if (item == "DisplayVersion") {
					if (uninstall || other_version == "") {
						other_version = data;
					}
					if (uninstall) {
						chosen_version = data;
					}
				}
			}
			if (chosen_name == "") {
				chosen_name = other_name;
			}
			if (chosen_version == "") {
				chosen_version = other_version;
			}
			name = chosen_name;
			version = chosen_version;
			return name != "" || version != "";
		}

		/**
		 * Read ''length'' bytes at ''offset''.
		 *
		 * @param input open installer
		 * @param offset file position
		 * @param length byte count
		 * @return the bytes
		 */
		private uint8[] read_at(GLib.FileInputStream input, int64 offset, int length) throws GLib.Error
		{
			if (length < 1) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			input.seek(offset, GLib.SeekType.SET);
			var dest = new uint8[length];
			var tmp = new uint8[64 * 1024];
			var got = 0;
			while (got < length) {
				var n = input.read(tmp);
				if (n < 1) {
					throw new InstallerError.REJECTED("could not read the installer");
				}
				var take = (int) n;
				if (take > length - got) {
					take = length - got;
				}
				GLib.Memory.copy((uint8*) dest + got, tmp, take);
				got += take;
				if ((int) n > take) {
					break;
				}
			}
			if (got != length) {
				throw new InstallerError.REJECTED("could not read the installer");
			}
			return dest;
		}
	}
}
