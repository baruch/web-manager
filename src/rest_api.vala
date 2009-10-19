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
	const string TANGOGPS_LOG_DIR = "/home/root/Maps/";

	private string json_normalize(string key) {
		return key.delimit(" -", '_');
	}

	private string hashtable_to_json(HashTable<string, Value?>? h, List<string> ulong_keys, List<string> hex_ulong_keys) {
		return_val_if_fail(h != null, "{}");

		string res = "{";
		bool first = true;
		foreach (var key in h.get_keys()) {
			if (!first)
				res = res.concat(",");
			else
				first = false;
			res = res.concat(json_normalize(key), ":");
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
		public virtual bool act_delete(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			return false;
		}
		public virtual bool act_post(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			return false;
		}
	}

	class DBusAPIAction : APIAction {
		public Soup.Message last_msg;
		public Soup.Server last_server;

		public void msg_resume(int code, string? status_desc = null) {
			if (status_desc != null)
				last_msg.set_status_full(code, status_desc);
			else
				last_msg.set_status(code);
			last_server.unpause_message(last_msg);
			last_msg = null;
			last_server = null;
		}

		public void msg_append_static(string s) {
			last_msg.response_body.append(Soup.MemoryUse.STATIC, s, s.size());
		}

		public void msg_append(string s) {
			last_msg.response_body.append(Soup.MemoryUse.COPY, s, s.size());
		}

		public virtual bool do_get(Soup.Message msg, GLib.HashTable<string, string>? query) {
			return false;
		}

		public override bool act_get(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			if (last_msg != null)
				msg_resume(KnownStatusCode.REQUEST_TIMEOUT);

			if (!do_get(msg, query))
				return false;

			last_msg = msg;
			last_server = server;
			server.pause_message(msg);
			return true;
		}
	}

	class GSMSignalStrength : DBusAPIAction {
		private dynamic DBus.Object gsm_network_bus;

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
			if (e != null) {
				msg_resume(KnownStatusCode.INTERNAL_SERVER_ERROR, e.message);
				return;
			}

			string status_json = hashtable_to_json(status, ulong_keys, hex_ulong_keys);
			last_msg.set_response("text/plain", Soup.MemoryUse.COPY, status_json, status_json.size());
			msg_resume(KnownStatusCode.OK);
		}

		public override bool do_get(Soup.Message msg, GLib.HashTable<string, string>? query) {
			this.gsm_network_bus.GetStatus(cb_get_status);
			return true;
		}
	}

	class GPXList : APIAction {
		public override bool act_get(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			msg.set_status(KnownStatusCode.OK);

			string result = "[";
			try {
				var directory = File.new_for_path(TANGOGPS_LOG_DIR);
				var enumerator = directory.enumerate_children(FILE_ATTRIBUTE_STANDARD_NAME.concat(",",FILE_ATTRIBUTE_STANDARD_TYPE,",",FILE_ATTRIBUTE_STANDARD_SIZE), 0, null);

				FileInfo file_info;
				bool first = true;
				while ((file_info = enumerator.next_file(null)) != null) {
					if (file_info.get_file_type() != FileType.REGULAR)
						continue;

					if (!file_info.get_name().has_suffix(".log"))
						continue;

					if (!first) {
						result = result.concat(",");
					}

					result = result.concat("{",
									"\"name\":\"", file_info.get_name(), "\",",
									"\"size\":", file_info.get_size().to_string(),
								"}");

					first = false;
				}

			} catch (Error e) {
				msg.set_status(KnownStatusCode.INTERNAL_SERVER_ERROR);
				result = "Error listing files: %s".printf(e.message);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, result, result.size());
				return true;
			}

			result = result.concat("]");
			msg.set_response("text/javascript", Soup.MemoryUse.COPY, result, result.size());
			return true;
		}
	}

	class GPXItem : APIAction {
		private void gpx_append(Soup.MessageBody body, string data) {
			body.append(Soup.MemoryUse.COPY, data, data.size());
		}

		private void write_gpx(Soup.MessageBody body, DataInputStream stream) {
			gpx_append(body, """<?xml version="1.0" encoding="UTF-8"?>
<gpx
  version="1.0"
  creator="GPSBabel - http://www.gpsbabel.org"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://www.topografix.com/GPX/1/0"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd">
""");

			gpx_append(body, "<trk><trkseg>");
			while (true) {
				size_t len;
				string line;
				try {
					line = stream.read_line(out len, null);
				} catch (GLib.Error e) {
					debug("Error while reading gpx logfile: %s", e.message);
					break;
				}
				if (line == null)
					break;
				string[] csv = line._strip().split(",");
				debug("Line length is %lu which split to %d parts", len, csv.length);
				if (csv.length != 7)
					continue;
				gpx_append(body, """<trkpt lat="%s" lon="%s">
  <ele>%s</ele>
  <speed>%s</speed>
  <course>%s</course>
  <hdop>%s</hdop>
  <time>%s</time>
  <fix>3d</fix>
</trkpt>""".printf(csv[0], csv[1], csv[2], csv[3], csv[4], csv[5], csv[6]));
			}
			gpx_append(body, "</trkseg></trk>");

			gpx_append(body, "</gpx>");
		}

		public override bool act_get(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			return_val_if_fail(query != null, false);
			string? filename = query.lookup("item");
			return_val_if_fail(filename != null, false);

			bool is_gpx = false;
			string tmp = query.lookup("format");
			if (tmp != null && tmp == "gpx")
				is_gpx = true;

			//TODO: need to sanitize filename, it must not begin with ../

			var f = File.new_for_path(TANGOGPS_LOG_DIR + filename);
			if (!f.query_exists(null)) {
				// File not found, let the user know
				msg.set_status(KnownStatusCode.NOT_FOUND);
				var response = "File not found %s".printf(filename);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, response, response.size());
				return true;
			}

			try {
				if (!is_gpx) {
					string contents;
					string etag;
					size_t len;
					bool success = f.load_contents(null, out contents, out len, out etag);
					debug("When loading content of file %s got etag %s size %lld", filename, etag, len);
					assert(success);

					msg.set_response("text/plain", Soup.MemoryUse.COPY, contents, contents.size());
				} else {
					var stream = new DataInputStream(f.read(null));
					write_gpx(msg.response_body, stream);
				}

				msg.set_status(KnownStatusCode.OK);
				return true;
			} catch (GLib.Error e) {
				msg.set_status(KnownStatusCode.INTERNAL_SERVER_ERROR);
				var response = "Internal server error: %s".printf(e.message);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, response, response.size());
				return true;
			}
		}

		public override bool act_delete(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			return_val_if_fail(query != null, false);
			string? filename = query.lookup("item");
			return_val_if_fail(filename != null, false);
			//TODO: need to sanitize filename, it must not begin with ../

			var f = File.new_for_path(TANGOGPS_LOG_DIR + filename);
			if (!f.query_exists(null)) {
				// File not found, let the user know
				msg.set_status(KnownStatusCode.NOT_FOUND);
				var response = "File not found %s".printf(filename);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, response, response.size());
				return true;
			}

			try {
				bool success = f.delete(null);
				string contents = success.to_string();
				msg.set_response("text/javascript", Soup.MemoryUse.COPY, contents, contents.size());
				msg.set_status(KnownStatusCode.OK);
				return true;
			} catch (GLib.Error e) {
				msg.set_status(KnownStatusCode.INTERNAL_SERVER_ERROR);
				var response = "Internal server error: %s".printf(e.message);
				msg.set_response("text/plain", Soup.MemoryUse.COPY, response, response.size());
				return true;
			}
		}
	}

	abstract class PimDBusAPIAction : DBusAPIAction {
		private static dynamic DBus.Object _messages_bus;
		public dynamic DBus.Object messages_bus { get {return impl_get_dbus_obj(ref this._messages_bus, "org.freesmartphone.opimd", "/org/freesmartphone/PIM/Messages", "org.freesmartphone.PIM.Messages");}}

		private static dynamic DBus.Object _contacts_bus;
		public dynamic DBus.Object contacts_bus {get {return impl_get_dbus_obj(ref this._contacts_bus, "org.freesmartphone.opimd", "/org/freesmartphone/PIM/Contacts", "org.freesmartphone.PIM.Contacts");}}

		private static dynamic DBus.Object _gsm_sms_bus;
		public dynamic DBus.Object gsm_sms_bus {get {return impl_get_dbus_obj(ref this._gsm_sms_bus, "org.freesmartphone.ogsmd", "/org/freesmartphone/GSM/Device", "org.freesmartphone.GSM.SMS");}}

		private string bus_last_path;
		private string bus_last_iface;
		private dynamic DBus.Object bus_last_obj;
		public dynamic DBus.Object get_bus(string iface, string path) {
			if (bus_last_path != null && bus_last_path == path && bus_last_iface == iface) {
				return bus_last_obj;
			}
			bus_last_obj = null;
			bus_last_path = path;
			bus_last_iface = iface;
			return impl_get_dbus_obj(ref this.bus_last_obj, "org.freesmartphone.opimd", path, iface);
		}
		public dynamic DBus.Object get_message_query_bus(string path) {
			return get_bus("org.freesmartphone.PIM.MessageQuery", path);
		}

		public static HashTable<string, string> charset_params;
		construct {
			if (charset_params == null) {
				charset_params = new HashTable<string,string>(str_hash, str_equal);
				charset_params.insert("charset", "utf-8");
			}
		}

		public void set_json_reply() {
			last_msg.response_headers.set_content_type("text/plain", charset_params);
			msg_resume(KnownStatusCode.OK);
		}

		private unowned DBus.Object? impl_get_dbus_obj(ref dynamic DBus.Object obj, string server, string path, string iface) {
			if (obj != null)
				return obj;

			try {
				var dbus = DBus.Bus.get(DBus.BusType.SYSTEM);
				obj = dbus.get_object(server, path, iface);
			} catch (DBus.Error e) {
				debug("DBus error while getting interface: %s", e.message);
			}
			return obj;
		}

		public bool glib_error(GLib.Error? e) {
			if (e != null) {
				debug("error: %d:%s", e.code, e.message);
				msg_resume(KnownStatusCode.INTERNAL_SERVER_ERROR, "Error: " + e.message);
				return true;
			}

			return false;
		}
	}

	class ContactsList : PimDBusAPIAction {
		private dynamic DBus.Object contacts_query;

		public override bool do_get(Soup.Message msg, GLib.HashTable<string, string>? query) {
			HashTable<string, Value?> null_query = new HashTable<string, Value?>(str_hash, str_equal);
			this.contacts_bus.Query(null_query, cb_query);
			return true;
		}

		private void cb_query(string path, GLib.Error? e) {
			if (glib_error(e))
				return;

			try {
				var dbus = DBus.Bus.get(DBus.BusType.SYSTEM);
				contacts_query = dbus.get_object("org.freesmartphone.opimd", path, "org.freesmartphone.PIM.ContactQuery");
				this.contacts_query.GetResultCount(cb_query_count);
			} catch (DBus.Error e) {
				debug("DBus error while getting interface: %s", e.message);
				msg_resume(KnownStatusCode.INTERNAL_SERVER_ERROR);
				return;
			}
		}

		private void cb_query_count(int count, GLib.Error? e) {
			if (glib_error(e))
				return;

			this.contacts_query.GetMultipleResults(count, cb_query_result);
		}

		private void cb_query_result(HashTable<string, Value?>[] results, GLib.Error? e) {
			if (glib_error(e))
				return;

			last_msg.response_body.append(Soup.MemoryUse.STATIC, "[", 1);

			List<string> dummy_list = new List<string>();
			for (uint idx = 0; idx < results.length; idx++) {
				string tmp = hashtable_to_json(results[idx], dummy_list, dummy_list);
				if (idx > 0)
					last_msg.response_body.append(Soup.MemoryUse.STATIC, ",\n", 2);
				last_msg.response_body.append(Soup.MemoryUse.COPY, tmp, tmp.size());
			}

			last_msg.response_body.append(Soup.MemoryUse.STATIC, "]", 1);
			set_json_reply();

			this.contacts_query.Dispose();
			this.contacts_query = null;
		}
	}

	class FoldersList : PimDBusAPIAction {
		public override bool do_get(Soup.Message msg, GLib.HashTable<string, string>? query) {
			this.messages_bus.GetFolderNames(cb_names);
			return true;
		}

		private void cb_names(string[] names, GLib.Error? e) {
			if (glib_error(e))
				return;

			msg_append_static("[");

			for (uint idx = 0; idx < names.length; idx++) {
				if (idx > 0)
					msg_append_static(",\n");
				msg_append_static("\"");
				msg_append(names[idx]);
				msg_append_static("\"");
			}
			msg_append_static("]");

			set_json_reply();
		}
	}

	class MessagesQuery : PimDBusAPIAction {
		private string last_path;

		public override bool do_get(Soup.Message msg, GLib.HashTable<string, string>? query) {
			GLib.HashTable<string, Value?> h = new GLib.HashTable<string, Value?>(str_hash, str_equal);
			this.messages_bus.Query(h, cb_query);
			return true;
		}

		private void cb_query(string? path, GLib.Error? e) {
			if (glib_error(e))
				return;

			if (path == null) {
				msg_resume(KnownStatusCode.INTERNAL_SERVER_ERROR, "no path received");
				return;
			}

			this.last_path = path;
			get_message_query_bus(path).GetResultCount(cb_count);
		}

		private void cb_count(int count, GLib.Error? e) {
			if (glib_error(e))
				return;

			debug("got count %d", count);
			get_message_query_bus(this.last_path).GetMultipleResults(count, cb_results);
		}

		private void cb_results(GLib.HashTable<string, Value?>[] results, GLib.Error? e) {
			if (glib_error(e))
				return;

			last_msg.response_body.append(Soup.MemoryUse.STATIC, "[", 1);
			List<string> dummy_list = new List<string>();
			for (uint idx = 0; idx < results.length; idx++) {
				string tmp = hashtable_to_json(results[idx], dummy_list, dummy_list);
				if (idx > 0)
					last_msg.response_body.append(Soup.MemoryUse.STATIC, ",\n", 2);
				last_msg.response_body.append(Soup.MemoryUse.COPY, tmp, tmp.size());
			}
			last_msg.response_body.append(Soup.MemoryUse.STATIC, "]", 1);

			set_json_reply();

			get_message_query_bus(this.last_path).Dispose();
			this.last_path = null;
		}
	}

	class Message : PimDBusAPIAction {
		private dynamic DBus.Object get_message_bus(string path) {
			return get_bus("org.freesmartphone.PIM.Message", path);
		}

		private string? get_query(GLib.HashTable<string, string>? query, string key) {
			if (query == null)
				return null;

			return query.lookup(key);
		}

		public override bool act_delete(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			string? path = get_query(query, "path");
			if (path != null) {
				get_message_bus(path).Delete();
				string status_json = "true";
				msg.set_response("text/plain", Soup.MemoryUse.COPY, status_json, status_json.size());
				msg.set_status(KnownStatusCode.OK);
			} else
				msg.set_status_full(KnownStatusCode.NOT_FOUND, "Missing path param");
			return true;
		}

		void hash_insert_val_str(GLib.HashTable<string, Value?> hash, string key, string val) {
			var v = Value(typeof(string));
			v.set_string(val);
			hash.insert(key, v);
		}

		void hash_insert_val_int(GLib.HashTable<string, Value?> hash, string key, int val) {
			var v = Value(typeof(int));
			v.set_int(val);
			hash.insert(key, v);
		}

		string last_content;
		string last_phone;
		public override bool act_post(Soup.Server server, Soup.Message msg, GLib.HashTable<string, string>? query) {
			debug("body: %lld,%s", msg.request_body.length, msg.request_body.data);
			var form = (GLib.HashTable<string,string>)Soup.form_decode(msg.request_body.data);

			var phone = form.lookup("phone");
			var content = form.lookup("content");

			var timestamp = Time.gm(time_t()).to_string();
			var timezone = "UTC";

			var data = new GLib.HashTable<string, Value?>(str_hash, str_equal);
			hash_insert_val_str(data, "Direction", "out");
			hash_insert_val_str(data, "Folder", "SMS");
			hash_insert_val_str(data, "Source", "SMS");
			hash_insert_val_int(data, "MessageSent", 0);
			hash_insert_val_int(data, "Processing", 1);
			hash_insert_val_str(data, "Recipient", phone);
			hash_insert_val_str(data, "Content", content);
			hash_insert_val_str(data, "Timestamp", timestamp);
			hash_insert_val_str(data, "Timezone", timezone);
			debug("Adding message to pim db: phone=%s timezone=%s timestamp='%s' content='%s'", phone, timezone, timestamp, content);
			this.messages_bus.Add(data, cb_msg_store);
			server.pause_message(msg);
			last_content = content;
			last_phone = phone;
			this.last_server = server;
			this.last_msg = msg;
			return true;
		}

		string last_path;
		private void cb_msg_store(string path, GLib.Error? e) {
			if (glib_error(e))
				return;

			var data = new GLib.HashTable<string, Value?>(str_hash, str_equal);
			//hash_insert_val_str(data, "alphabet", "ucs2"); // DOCS say usc2 but name is officialy ucs2
			//data.insert("status-report-request", true);
			//data.inserT("message-reference", random_int);
			debug("Send SMS to phone=%s content='%s'", this.last_phone, this.last_content);
			this.gsm_sms_bus.SendMessage(this.last_phone, this.last_content, data, cb_msg_sent);
			last_path = path;
		}

		private void cb_msg_sent(int transaction_index, string timestamp, GLib.Error? e) {
			if (glib_error(e))
				return;

			var data = new GLib.HashTable<string, Value?>(str_hash, str_equal);
			data.insert("Processing", 0);
			data.insert("MessageSent", 1);
			data.insert("SMS-message-reference", transaction_index);
			data.insert("SMS-SMSC-timestamp", timestamp);
			debug("Update pim message path=%s timestamp='%s' transaction=%d", this.last_path, timestamp, transaction_index);
			this.get_message_bus(last_path).Update(data);

			last_msg.response_body.append(Soup.MemoryUse.STATIC, "true", 4);
			set_json_reply();
		}
	}

	class RestAPI : Object {
		HashTable<string, APIAction> actions;

		construct {
			actions = new HashTable<string, APIAction>(str_hash, str_equal);
			actions.insert("gsm/status", new GSMSignalStrength());
			actions.insert("gpx/list", new GPXList());
			actions.insert("gpx/item", new GPXItem());
			actions.insert("contacts/list", new ContactsList());
			actions.insert("messages/folders", new FoldersList());
			actions.insert("messages/list", new MessagesQuery());
			actions.insert("message", new Message());
		}

		public bool process_message(Soup.Server server, Soup.Message msg, string path, GLib.HashTable<string, string>? query) {
			debug("rest path %s".printf(path));
			APIAction? action = actions.lookup(path);
			if (action != null) {
				bool res = false;
				if (msg.method == "GET")
					res = action.act_get(server, msg, query);
				else if (msg.method == "DELETE")
					res = action.act_delete(server, msg, query);
				else if (msg.method == "POST")
					res = action.act_post(server, msg, query);
				else {
					// Unknown method
					msg.set_status(KnownStatusCode.METHOD_NOT_ALLOWED);
					res = true;
				}

				return res;
			}
			return false;
		}
	}	
}
