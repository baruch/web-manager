/*
 *  Copyright (C) 2009
 *      Authors (alphabetical) :
 *              Baruch Even <baruch@ev-en.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU Public License as published by
 *  the Free Software Foundation; version 2 of the license.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Lesser Public License for more details.
 */
using GLib;
using Soup;

namespace WebManager {
	private string hashtable_to_json(HashTable<string, Value?>? h, List<string> ulong_keys, List<string> hex_ulong_keys) {
		return_val_if_fail(h != null, "{}");

		string res = "{";
		bool first = true;
		foreach (var key in h.get_keys()) {
			if (!first)
				res = res.concat(",");
			else
				first = false;
			res = res.concat("\"", key, "\":");
			Value? val = h.lookup(key);
			if (val == null)
				continue;

			Value strval = Value(typeof(string));
			val.transform(ref strval);
			string val_str = strval.get_string();
			res = res.concat("\"", val_str, "\"");
		}

		return res.concat("}");
	}

	abstract class APIAction : Object {
		public abstract bool act_get(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query);
	}

	class GSMSignalStrength : APIAction {
		private dynamic DBus.Object gsm_network_bus;
		private Soup.Message? last_msg;
		private weak Soup.Server? last_server;

		static List<string> ulong_keys;
		static List<string> hex_ulong_keys;

		construct {
			try {
				var dbus = DBus.Bus.get(DBus.BusType.SYSTEM);
				this.gsm_network_bus = dbus.get_object("org.freesmartphone.ogsmd", "/org/freesmartphone/GSM/Device", "org.freesmartphone.GSM.Network");
			} catch (DBus.Error e) {
				debug("DBus error while getting interface: %s", e.message);
			}

			if (ulong_keys == null) {
				ulong_keys = new List<string>();
				ulong_keys.prepend("code");
				ulong_keys.prepend("strength");
			}
			if (hex_ulong_keys == null) {
				hex_ulong_keys = new List<string>();
				hex_ulong_keys.prepend("cid");
				hex_ulong_keys.prepend("lac");
			}
		}

		private void cb_get_status(HashTable<string, Value?> status, GLib.Error? e) {
			last_server.unpause_message(last_msg);

			if (e != null) {
				last_msg.set_status_full(KnownStatusCode.INTERNAL_SERVER_ERROR, e.message);
				return;
			}

			last_msg.set_status(KnownStatusCode.OK);
			string status_json = hashtable_to_json(status, ulong_keys, hex_ulong_keys);
			last_msg.set_response("text/plain", Soup.MemoryUse.COPY, status_json, status_json.len());
		}

		public override bool act_get(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			if (last_msg != null) {
				msg.set_status(KnownStatusCode.REQUEST_TIMEOUT);
				server.unpause_message(last_msg);
				last_msg = null;
			}

			this.gsm_network_bus.GetStatus(cb_get_status);
			server.pause_message(msg);
			last_msg = msg;
			last_server = server;
			return true;
		}
	}

	class RestAPI : Object {
		HashTable<string, APIAction> actions;

		construct {
			actions = new HashTable<string, APIAction>(str_hash, str_equal);
			actions.insert("gsm/status", new GSMSignalStrength());
		}

		public bool process_message(Soup.Server server, Soup.Message msg, string path, GLib.HashTable<string, string>? query) {
			debug("rest path %s".printf(path));
			APIAction? action = actions.lookup(path);
			if (action != null) {
				bool res = false;
				if (msg.method == "GET")
					res = action.act_get(server, msg, query);
				else {
					// Unknown method
					msg.set_status(KnownStatusCode.METHOD_NOT_ALLOWED);
					res = true;
				}

				if (res) {
					msg.set_status(KnownStatusCode.OK);
				}
				return res;
			}
			return false;
		}
	}	
}
