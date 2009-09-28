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

namespace WebManager {
	
	class Deamon {

		private void init() {
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
