/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

include "corsaair/server/spitfire/SimpleSocketServer.as";
include "corsaair/server/spitfire/SimpleSocketServerSelect.as";
include "corsaair/server/spitfire/SimpleSocketServerSelect2.as";
include "corsaair/server/spitfire/SimpleSocketServerSelect3.as";
include "corsaair/server/spitfire/SimpleSocketServerSelect4.as";
include "corsaair/server/spitfire/SimpleSocketServerSelect5.as";

import corsaair.server.spitfire.*;
import flash.system.Worker;

// example1
/*
var server = new SimpleSocketServer();
    server.main();
*/

// example2
/*
var server = new SimpleSocketServerSelect();
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
*/

// example3
/*
var server = new SimpleSocketServerSelect2();
    server.main();
*/

// example4
/*
var server = new SimpleSocketServerSelect3();
    server.sleepTime = 1000; // try diff values like: 10, 100, 1000, etc.
    server.main();
*/

// example5
/*
var server = new SimpleSocketServerSelect4();
    server.sleepTime = 1000;
    server.main();
*/

// example6
var server = new SimpleSocketServerSelect5();
    server.sleepTime = 1000;

    if( Worker.current.isPrimordial )
    {
        trace( ">> primordial <<" );
        server.main();    
    }
    else
    {
        trace( ">> background <<" );
        server.registerNewArrival();
    }
    
