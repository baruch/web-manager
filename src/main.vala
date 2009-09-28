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

		private int do_default_handler(Soup.Message msg, GLib.HashTable<string, string>? query) {
			string response_text = "<html><head><title>Default page</title></head><body><p>This is just the default page</p></body></html>";
			msg.set_response("text/html", Soup.MemoryUse.COPY, response_text, response_text.len());
			return KnownStatusCode.OK;
		}

		private void default_handler(Soup.Server server, Soup.Message msg, string path, GLib.HashTable<string, string>? query, Soup.ClientContext client) {
			msg.set_status(do_default_handler(msg, query));
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
