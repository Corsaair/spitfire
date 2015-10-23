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
    import C.stdlib.*;
    import C.unistd.*;
    
    import flash.utils.ByteArray;
    

    /**
     * A simple socket server.
     * 
     * This mainyl show how you use BSD sockets to setup a listenign server,
     * the server does not have a loop to listen on multiple connections
     * to deal with numerous clients.
     * 
     * You run the server, connect to it with telnet or netcat,
     * the server send a message to the client and then close the connection.
     * 
     * @see http://beej.us/guide/bgnet/output/html/singlepage/bgnet.html#simpleserver A Simple Stream Server
     */
    public class SimpleSocketServer
    {

        // the port users will be connecting to
        public const PORT:String = "3490";

        // how many pending connections queue will hold
        public const BACKLOG:uint = 10;

        public function SimpleSocketServer()
        {
            super();
        }

        /* Note:
           This is our first server
           we do the basic and the very raw stuff
           using BSD sockets with comments :)

           this code is ported directly from C source code
           http://beej.us/guide/bgnet/output/html/singlepage/bgnet.html#simpleserver
           from the excellent
           Beej's Guide to Network Programming
           Using Internet Sockets
        */
        public function main():void
        {
            // listen on sock_fd
            var sockfd:int;
            // new connection on new_fd
            var new_fd:int;

            var hints:addrinfo = new addrinfo();
            var servinfo:addrinfo;

            /* Note:
               With BSD sockets the constants are very important
               it's how we configure everything

               ai_family = AF_UNSPEC
               if we want to use either IPv4 or IPv6

               ai_family = AF_INET
               to use only IPv4

               ai_family = AF_INET6
               to use only IPv6

               SOCK_STREAM for TCP (stream) sockets
               SOCK_DGRAM for UDP (datagram) sockets
            */
            hints.ai_family   = AF_UNSPEC;
            hints.ai_socktype = SOCK_STREAM;
            hints.ai_flags    = AI_PASSIVE; // use my IP

            /* Note:
               getaddrinfo() works a bit differently compared to C
               instead of passing a list by reference and return an int 
               our AS3 getaddrinfo()
               - return null if an error occured
                 and will fill the details into the CEAIrror object
               - or return an array of addrinfo found
            */
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
                    trace( "server: socket" )
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
                    trace( "server: bind" );
                    trace( new CError( "", errno ) );
                    continue;
                }

                /* Note:
                   If we reach here that means we could
                   open a socket and bind to it
                */
                break;
            }

            /* Note:
               If this happen that means
               we looped trough all the address of getaddrinfo()
               but we could not open/bind any of them
            */
            if( servinfo == null )
            {
                trace( "server: failed to bind" );
                exit( 1 );
            }

            /* Note:
               that's the basic of a "socket server"
               - socket() : Create an endpoint for communication.
               - bind()   : Bind a name to a socket.
               - listen() : Listen for socket connections
                            and limit the queue of incoming connections.
                
               socket() is mainly describing what kind of socket we want to use
               and then return a file descriptor (the ID of the socket if you want)

               bind() is here to "connect" the socket ID to a network interface
               on the same computer you could have different IP address:
               127.0.0.1 the localhost
               192.168.0.1 the IP adress on your local network
               255.165.225.235 the IP adress assigned by your ISP
               etc.

               and finally listen() is here to say on which port we want
               to receive data, or which service
               port 80 is for HTTP web server
               port 21 is for FTP server
               etc.
            */
            var listening:int = listen( sockfd, BACKLOG );
            if( listening == -1 )
            {
                trace( "listen" );
                trace( new CError( "", errno ) );
                exit( 1 );
            }


            trace( "server: waiting for connections..." );

            var client_addr:sockaddr_in = new sockaddr_in();

            // main accept() loop
            while( 1 )
            {
                new_fd = accept( sockfd, client_addr );
                if( new_fd == -1 )
                {
                    trace( "accept" );
                    trace( new CError( "", errno ) );
                    continue;
                }

                var s:String = inet_ntop( client_addr.sin_family, client_addr );
                if( !s )
                {
                    trace( "inet_ntop" );
                    trace( new CError( "", errno ) );
                    continue;
                }
                trace( "server: got connection from " + s );

                /* Note:
                   we prepare the message into a ByteArray and send it

                   If you comapre with server.c you will see that
                   we do not use fork()
                   this is on purpose
                   fork() is a very unixy thing that just does not work
                   under Windows, but next example will show how to do
                   like fork() but with Workers :)
                */
                var msg:String = "Hello, world!\n";
                var bytes:ByteArray = new ByteArray();
                    bytes.writeUTFBytes( msg );
                    bytes.position = 0;
                var sent:int = send( new_fd, bytes );
                if( sent == -1 )
                {
                    trace( "send" );
                    trace( new CError( "", errno ) );
                    continue;
                }
                else
                {
                    trace( "sent " + sent + " bytes to the client" );
                    break;
                }

            }

            trace( "disconnecting client" );
            close( new_fd );

            trace( "shutting down server" );
            close( sockfd );

            exit( 0 );

        }

    }
}
