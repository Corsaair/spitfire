/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

package corsaair.server.spitfire
{

    import C.errno.*;
    import C.arpa.inet.*;
    import C.netdb.*;
    import C.netinet.*;
    import C.sys.socket.*;
    import C.sys.select.*;
    import C.stdlib.*;
    import C.unistd.*;
    
    import flash.utils.ByteArray;
    

    /**
     * A simple socket server upgrade 1.
     * 
     * This time we do use a loop to listen and interact with multiple clients.
     * 
     * @see http://beej.us/guide/bgnet/output/html/singlepage/bgnet.html#select a cheezy multiperson chat server
     */
    public class SimpleSocketServerSelect
    {

        // the port users will be connecting to
        public const PORT:String = "3490";

        // how many pending connections queue will hold
        public const BACKLOG:uint = 10;

        public function SimpleSocketServerSelect()
        {
            super();
        }

        public function showAddressInfo1():void
        {
            var hints:addrinfo = new addrinfo();
            var info:addrinfo;

            /* Note:
               because we want to bind
               eg. ai_flags = AI_PASSIVE
               it will automatically use the wildcard address 0.0.0.0
               which means you're binding to every IP address on your machine
            */
            hints.ai_family   = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_flags    = AI_PASSIVE; // indicate we want to bind

            var eaierr:CEAIrror = new CEAIrror();
            var addrlist:Array  = getaddrinfo( null, "http", hints, eaierr );

            if( !addrlist )
            {
                throw eaierr;
            }

            trace( "found " + addrlist.length + " addresses" );
            for( var i:uint = 0; i < addrlist.length; i++ )
            {
                info = addrlist[i];
                trace( "[" + i + "] = " + inet_ntop( info.ai_family, info.ai_addr ) );
            }
        }

        public function showAddressInfo2():void
        {
            var hints:addrinfo = new addrinfo();
            var info:addrinfo;

            /* Note:
               Without ai_flags = AI_PASSIVE
               the first local address will be the loopback
               eg. 127.0.0.1
            */
            hints.ai_family   = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;

            var eaierr:CEAIrror = new CEAIrror();
            var addrlist:Array  = getaddrinfo( null, "http", hints, eaierr );

            if( !addrlist )
            {
                throw eaierr;
            }

            trace( "found " + addrlist.length + " addresses" );
            for( var i:uint = 0; i < addrlist.length; i++ )
            {
                info = addrlist[i];
                trace( "[" + i + "] = " + inet_ntop( info.ai_family, info.ai_addr ) );
            }
        }

        public function showAddressInfo3( hostname:String = "" ):void
        {
            /* Note:
               gethostname() will obtain your local hostname
               and use the IP address used on your local network
               for ex: 192.168.0.xyz

               if you pass a custom hostname like "www.as3lang.org"
               it will resolve to the IP address of that remote hostname

               it can also return many IP addresses depending on
               the remote hostname configuration, for ex: with something
               like cloudlfare it can  returns 2 or more addresses
               etc.
            */
            if( hostname == "" )
            {
                hostname = gethostname();
            }
            
            trace( "hostname = " + hostname );

            var hints:addrinfo = new addrinfo();
            var info:addrinfo;

            hints.ai_family   = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;

            var eaierr:CEAIrror = new CEAIrror();
            var addrlist:Array  = getaddrinfo( hostname, "http", hints, eaierr );

            if( !addrlist )
            {
                throw eaierr;
            }

            trace( "found " + addrlist.length + " addresses" );
            for( var i:uint = 0; i < addrlist.length; i++ )
            {
                info = addrlist[i];
                trace( "[" + i + "] = " + inet_ntop( info.ai_family, info.ai_addr ) );
            }
        }

        public function main():void
        {
            var sockfd:int; // listening socket descriptor
            
            var new_fd:int;  // newly accept()ed socket descriptor

            var hints:addrinfo = new addrinfo();
            var servinfo:addrinfo;

            hints.ai_family   = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_flags    = AI_PASSIVE; // use my IP

            var eaierr:CEAIrror = new CEAIrror();
            var addrlist:Array  = getaddrinfo( null, PORT, hints, eaierr );

            if( !addrlist )
            {
                throw eaierr;
            }
            
            var option:int;
            var bound:int;

            // loop through all the results and bind to the first we can
            for( var i:uint = 0; i < addrlist.length; i++ )
            {
                servinfo = addrlist[i];

                sockfd = socket( servinfo.ai_family, servinfo.ai_socktype, servinfo.ai_protocol );
                if( sockfd == -1 )
                {
                    trace( "selectserver: socket" )
                    trace( new CError( "", errno ) );
                    continue;
                }

                option = setsockopt( sockfd, SOL_SOCKET, SO_REUSEADDR, 1 );
                if( option == -1 )
                {
                    trace( "setsockopt" );
                    trace( new CError( "", errno ) );
                    exit( 1 );
                }

                bound = bind( sockfd, servinfo.ai_addr );
                if( bound == -1 )
                {
                    close( sockfd );
                    trace( "selectserver: bind" );
                    trace( new CError( "", errno ) );
                    continue;
                }

                break;
            }

            if( servinfo == null )
            {
                trace( "selectserver: failed to bind" );
                exit( 1 );
            }

            var listening:int = listen( sockfd, BACKLOG );
            if( listening == -1 )
            {
                trace( "listen" );
                trace( new CError( "", errno ) );
                exit( 1 );
            }


            trace( "selectserver: waiting for connections..." );

            /* Note:
               so what is a select() server exactly ?

               it is simple
               - you use 'fd_set' to delcare sets of file descriptor (like an Array)
               - you use FD_SOMETHING macros to read/write/clear data from those sets
                 FD_ZERO to reset a 'fd_set'
                 FD_ISSET to know if a socket descriptor is set
                 FD_SET to set a socket descriptor into a set
                 FD_CLR to remove a socket descriptor from a set
               - then you use the function select()
                 to loop trough all those sets
               
               And you know what, I messed up the implementation of select()
               "as is" it does not work or half-work, ok my bad

               but wait ...
               a 'fd_set' is like an array so you know what
               it's pretty simple to do like select() without select()
               simply put
               - add each new socket descriptor into an array
               - loop trough the array
               - detect if the socket is readable

               humm how to detect if a socket is readable ?
               well in C.sys.select.* you can find 3 functions
               isReadable()    - Test if a socket is ready for reading.
               isWritable()    - Test if a socket is ready for writing.
               isExceptional() - Test if a socket has an exceptional condition pending.
               and those are working :)
               (long sotry short strangely under the hood they alos use 'fd_set' but in
               a very simple stupid way that works)
            */


            // reset the list
            var connections:Array = [];
            
            // add the listener to the master set
            connections.push( sockfd );
            trace( "selectserver: server on socket " + sockfd );
            
            var run:Boolean = true;

            /* Note:
               it can be a for(;;), a while(1), a while(true), etc.
               but yes you get it, here we need an infinite loop

               no worries it's Redtamarin, not Flash/AIR
               we can loop forever it will not cause a script timeout
            */
            // main loop
            for(;;)
            {
            	
            	if( !run )
            	{
            		break;
            	}

                // run through the existing connections looking for data to read
                for( var j:uint = 0; j < connections.length; j++ )
                {
                    //trace( "selectserver: selecting socket " + connections[j] );

                    /* Note:
                       if the socket descriptor is readable
                       then we do our work
                       
                       ATTENTION
                       in 'connections' you have both the server and all the clients
                       - for the server
                         being readable mean someone try to connect to the server
                         and if no one try to connect then the server is not readable
                       - for the client
                         being readable mean the client try to send data to the server
                         and if the client do nto send data then it is not readable

                       so here the loop works like
                       - loop trough all the socket descriptor
                       - only do work if there is osmethign to read
                         - if server, create a new connection
                         - if client, read the client data
                       - otherwise keep looping
                    */
                    // we got one!!
                    if( isReadable( connections[j] ) )
                    {
                        // the server
                        if( connections[j] == sockfd )
                        {
                            // handle new connections
                            var client_addr:sockaddr_in = new sockaddr_in();
                            new_fd = accept( sockfd, client_addr );
                            if( new_fd == -1 )
                            {
                                trace( "accept" );
                                trace( new CError( "", errno ) );
                            }
                            else
                            {
                                // add to master set
                                connections.push( new_fd );
                                
                                // keep track of the max
                                /* Note:
                                   the array index does that for us
                                */

                                var s:String = inet_ntop( client_addr.sin_family, client_addr );
                                trace( "selectserver: new connection from " + s  + ", socket " + new_fd );

                                var msg_out:String = "Hello, world!\n";
                                var bytes_out:ByteArray = new ByteArray();
                                    bytes_out.writeUTFBytes( msg_out );
                                    bytes_out.position = 0;

                                var sent:int = send( new_fd, bytes_out );
                                if( sent == -1 )
                                {
                                    trace( "send" );
                                    trace( new CError( "", errno ) );
                                }
                                else
                                {
                                    trace( "sent " + sent + " bytes to the client " + new_fd );
                                }

                            }

                        }
                        else
                        {
                            // handle data from a client
                            var msg_in:String;
                            var bytes_in:ByteArray = new ByteArray();

                            var received:int = recv( connections[j], bytes_in );
                            if( received <= 0 )
                            {
                                // got error or connection closed by client
                                if( received == 0 )
                                {
                                    // connection closed
                                    trace( "selectserver: socket " + connections[j] + " hung up" );
                                }
                                else
                                {
                                    trace( "recv" );
                                    trace( new CError( "", errno ) );
                                }

                                close( connections[j] ); // bye!

                                // remove from master set
                                connections.splice( j, 1 );
                            }
                            else
                            {
                                // we got some data from a client
                                trace( "received " + received + " bytes from client " + connections[j] );
                                bytes_in.position = 0;
                                msg_in = bytes_in.readUTFBytes( bytes_in.length );
                                msg_in = msg_in.split( "\n" ).join( "" );
                                trace( connections[j] + " : " + msg_in );

                                if( msg_in == "shutdown" )
                                {
                                	trace( "selectserver: received 'shutdown' command" );
                                	run = false;
                                	break;
                                }
                            }

                        } // END handle data from client

                    } // END got new incoming connection

                } // END looping through file descriptors

            } // END for(;;)--and you thought it would never end!

            trace( "selectserver: connections left [" + connections + "]" );

            /* Note:
               properly close all clients before
            */
            for( var k:uint = 0; k < connections.length; k++ )
            {
            	if( connections[k] != sockfd )
            	{
            		trace( "selectserver: terminate " + connections[k] );
            		close( connections[k] );
            		connections.splice( k, 1 );
            		k = 0; //rewind
            	}
            }

            trace( "shutting down server" );
            shutdown( sockfd, SHUT_RDWR );
            close( sockfd );

            exit( 0 );

        }

    }
}
