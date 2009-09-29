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
	
	class Deamon {
		Soup.Server server;

		private string simple_html(string title, string message) {
			return "<html><head><title>%s</title></head><body><p>%s</p></body></html>".printf(title, message);
		}

		private string mimetype_for_file(string path) {
			if (path.has_suffix(".html"))
				return "text/html";
			else if (path.has_suffix(".css"))
				return "text/css";
			else if (path.has_suffix(".js"))
				return "text/javascript";
			return "text/plain";
		}

		private int do_file_not_found(Soup.Message msg, string path) {
			string response_text = simple_html("File not found", "Requsted file %s was not found".printf(path));
			msg.set_response("text/html", Soup.MemoryUse.COPY, response_text, response_text.len());
			return KnownStatusCode.NOT_FOUND;

		}

		private int do_default_handler(Soup.Message msg, string path, GLib.HashTable<string, string>? query) {
			string concat_path;
			if (path.has_suffix("/")) {
				concat_path = path.concat("index.html");
				path = concat_path;
			}
			File fileobj = File.new_for_path(".".concat(path));
			if (!fileobj.query_exists(null))
				return do_file_not_found(msg, path);

			string content;
			size_t content_len;
			string mimetype = mimetype_for_file(path);
			try {
				bool ret = fileobj.load_contents(null, out content, out content_len, null);
				assert(ret == true);
			} catch (GLib.Error e) {
				content = simple_html("Error loading file", "Failed to load file %s, errno: %d, msg: %s".printf(path, e.code, e.message));
				content_len = content.len();
				mimetype = "text/html";
			}

			msg.set_response(mimetype, Soup.MemoryUse.COPY, content, content_len);
			return KnownStatusCode.OK;
		}

		private void default_handler(Soup.Server server, Soup.Message msg, string path, GLib.HashTable<string, string>? query, Soup.ClientContext client) {
			msg.set_status(do_default_handler(msg, path, query));
		}

		private void init() {
			server = new Soup.Server(SERVER_PORT, 80);
			server.add_handler("/", default_handler);
			server.run_async();
		}

		private void uninit() {
		}

		public void run(string[] args) {
			message("Starting web-manager");
			var loop = new MainLoop(null, false);
			init();
			message("Started web-manager");
			
			/* Run main loop */
			loop.run();
			
			message("Stoping web-manager");
			uninit();
			message("Stoped web-manager");
		}
		
		public static void main(string[] args) {
			Deamon deamon = new Deamon();
			deamon.run(args);
		}
	}
}
