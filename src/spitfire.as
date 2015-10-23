/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

include "corsaair/server/spitfire/SimpleSocketServer.as";
include "corsaair/server/spitfire/SimpleSocketServer1.as";

import corsaair.server.spitfire.*;

// example1
/*
var server = new SimpleSocketServer();
*/

// example2
var server = new SimpleSocketServer1();
	server.showAddressInfo1();
	server.showAddressInfo2();
	server.showAddressInfo3();
	server.showAddressInfo3( "localhost" );

	// pass trough cloudflare
	server.showAddressInfo3( "www.corsaair.com" );

	// direct to the server
	server.showAddressInfo3( "www.as3lang.org" );

	// more example
	server.showAddressInfo3( "www.google.com" );
	server.showAddressInfo3( "www.yahoo.com" );
	server.showAddressInfo3( "www.cloudflare.com" );

	server.main();

