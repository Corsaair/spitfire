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
     * A simple socket server upgrade 2.
     * 
     * Let's clean up the code and reorganise it into methods
     * to spearate responsibility.
     * 
     */
    public class SimpleSocketServerSelect2
    {

        // the port users will be connecting to
        public const PORT:String = "3490";

        // how many pending connections queue will hold
        public const BACKLOG:uint = 10;

        private var _address:Array;   // list of addresses
        private var _info:addrinfo;   // server selected address
        
        private var _run:Boolean;     // run the server loop


        public var serverfd:int;      // server socket descriptor
        public var selected:int;      // selected socket descriptor
        public var connections:Array; // list of socket descriptor

        public function SimpleSocketServerSelect2()
        {
            super();

            _address    = [];
            _info       = null;
            _run        = true;
            serverfd    = -1;
            selected    = -1;
            connections = [];
        }

        /**
         * @private
         * 
         * Use getaddrinfo() to obtain a list of IP addresses we can use
         * loop trough those addresses and bind to the first one we can
         * 
         * Two possible outcome
         * 
         * - we found an address and boudn to it
         *   we set the _info object with the address
         *   then we return the socket descriptor
         * 
         * - we exhausted the list of addresses
         *   without binding to any of them
         *   then our _info object is not set
         *   we return an unusable socket descriptor
         */
        private function _getBindingSocket():int
        {

            var hints:addrinfo = new addrinfo();
                hints.ai_family   = AF_UNSPEC;
                hints.ai_socktype = SOCK_STREAM;
                hints.ai_flags    = AI_PASSIVE; // indicates we want to bind

            var info:addrinfo;

            var eaierr:CEAIrror = new CEAIrror();
            var addrlist:Array  = getaddrinfo( null, PORT, hints, eaierr );

            if( !addrlist )
            {
                throw eaierr;
            }

            var sockfd:int;
            var option:int;
            var bound:int;

            var i:uint;
            var len:uint = addrlist.length;
            for( i = 0; i < len; i++ )
            {
                info = addrlist[i];

                sockfd = socket( info.ai_family, info.ai_socktype, info.ai_protocol );
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

                bound = bind( sockfd, info.ai_addr );
                if( bound == -1 )
                {
                    close( sockfd );
                    trace( "selectserver: bind" );
                    trace( new CError( "", errno ) );
                    continue;
                }

                // we save the selected addrinfo
                _info = info;
                break;
            }

            // we merge the addresses found into our list of address
            _address = _address.concat( addrlist );

            // we return the socket descriptor
            return sockfd;
        }

        /**
         * @private
         * 
         * Loop trough all the clients connections.
         * 
         * Yes this is how we do multiplexing I/O
         * without really using select()
         * 
         * All the secret is with isReadable()
         * from that point we know we can read on
         * the socket and this lead to 2 clear paths
         * 
         * - the server
         *   reading on the server socket means
         *   accepting a new connection with accept()
         * 
         * - the clients
         *   reading on a client socket means
         *   reading data from the client with recv()
         * 
         * IMPORTANT:
         * both accept() and recv() are blocking
         * which means you can freeze your server loop
         * if something is misshandled or take too long
         * (this will be explained in the next example)
         */
        private function _loopConnections():void
        {
            var i:uint;
            var len:uint = connections.length;
            
            for( i = 0; i < len; i++ )
            {
                selected = connections[i];

                if( isReadable( selected ) )
                {

                    if( selected == serverfd )
                    {
                        _handleNewConnections();
                    }
                    else
                    {
                        _handleClientData();
                    }

                }

            }

        }

        /**
         * @private
         * 
         * Block on accept()
         * if accepted
         * - add the new socket descriptor to the connections
         * - send a welcome message to the client
         */
        private function _handleNewConnections():void
        {
            // handle new connections

            var new_fd:int;  // newly accept()ed socket descriptor
            var client_addr:sockaddr_in = new sockaddr_in();
            
            new_fd = accept( serverfd, client_addr );

            if( new_fd == -1 )
            {
                trace( "accept" );
                trace( new CError( "", errno ) );
            }
            else
            {
                connections.push( new_fd );
                
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

        /**
         * @private
         * 
         * Block on recv()
         * if receiving data
         * - write the data to the server log
         * - check for the "shutdown" command
         * 
         * How do we know we are not receiving data ?
         * if you try to recv() on a disconected client
         * you will automatically recevie 0 which means
         * the client disconnected or hung up.
         * Or you will receive a negative integer
         * for signalling an error.
         * 
         * In both case, we want to close the socket ot the client
         * and remove it from the connections list.
         */
        private function _handleClientData():void
        {
            // handle data from a client

            var msg_in:String;
            var bytes_in:ByteArray = new ByteArray();

            var received:int = recv( selected, bytes_in );
            if( received <= 0 )
            {
                // got error or connection closed by client
                if( received == 0 )
                {
                    // connection closed
                    trace( "selectserver: socket " + selected + " hung up" );
                }
                else
                {
                    trace( "recv" );
                    trace( new CError( "", errno ) );
                }

                close( selected ); // bye!

                // remove from master set
                _removeClient( selected );
            }
            else
            {
                // we got some data from a client
                trace( "received " + received + " bytes from client " + selected );
                bytes_in.position = 0;
                msg_in = bytes_in.readUTFBytes( bytes_in.length );
                msg_in = msg_in.split( "\n" ).join( "" );
                trace( selected + " : " + msg_in );

                if( msg_in == "shutdown" )
                {
                    trace( "selectserver: received 'shutdown' command" );
                    _run = false;
                }
            }
        }

        /**
         * @private
         * 
         * add a client to list of connections
         * so far a 'client' is only the integer of a socket descriptor
         * 
         * a client can be as well the current server than a remobe client
         */
        private function _addClient( sd:int ):void
        {
            connections.push( sd );
        }

        /**
         * @private
         * 
         * remove a client from the list of connections
         */
        private function _removeClient( sd:int ):void
        {
            /* Note:
               protection from removing the server socket descriptor
               which would disconnect/crash all other clients
            */
            if( sd == serverfd )
            {
                return;
            }

            var i:uint;
            var len:uint = connections.length;
            var desc:int;
            for( i = 0; i < len; i++ )
            {
                desc = connections[i];
                if( desc == sd )
                {
                    connections.splice( i, 1 );
                }
            }
        }

        /**
         * @private
         * 
         * close the socket descriptor and remove it from the list of connections
         * we use that to clean after ourselves
         * but in most case if the server process were to crash
         * all the descriptor would be automatically closed as
         * they depend on this process.
         * 
         * Alternatively you can also use this to disconnect all or parts of the clients.
         */
        private function _closeAndRemoveAllClients( removeServer:Boolean = false ):void
        {
            var i:uint;
            var desc:int;
            for( i = 0; i < connections.length; i++ )
            {
                desc = connections[i];

                if( !removeServer && (desc == serverfd) )
                {
                    continue;
                }

                trace( "selectserver: terminate " + desc );
                close( desc );
                connections.splice( i, 1 );
                i = 0; //rewind
            }
        }


        public function main():void
        {
            /* Note:
               find our IP address and bind thesocket to it
               in general the IP will be 0.0.0.0
               which means listen on all interfaces
            */
            serverfd = _getBindingSocket();

            /* Note:
               Verify that we have selected an address
               if not it is a fatal error.
               eg. the loop trough the address info
               did not find an address
            */
            if( _info == null )
            {
                trace( "selectserver: failed to bind" );
                exit( 1 );
            }

            /* Note:
               The last part of the server setup is to listen()
               which means "I'm ready to receive data".

               If the server can not listen it is a fatal error.

               About BACKLOG
               see http://pubs.opengroup.org/onlinepubs/9699919799/functions/listen.html
               the backlog is here to limit the queue of incoming connections
               it will not handle multiple connections
               eg. that's the difference between queueing and multiplexing

               The backlog argument provides a hint to the implementation
               which the implementation shall use to limit the number of
               outstanding connections in the socket's listen queue.
               Implementations may impose a limit on backlog and silently
               reduce the specified value.
               Normally, a larger backlog argument value shall result in
               a larger or equal length of the listen queue.
               Implementations shall support values of backlog up to SOMAXCONN,
               defined in `C.sys.socket`.
            */
            var listening:int = listen( serverfd, BACKLOG );
            if( listening == -1 )
            {
                trace( "listen" );
                trace( new CError( "", errno ) );
                exit( 1 );
            }

            trace( "selectserver: waiting for connections..." );

            // the server is always the first client to be added to the connections
            _addClient( serverfd );
            trace( "selectserver: server on socket " + serverfd );
            
            /* Note:
               main server loop

               Keep the server looping as long as
               run == true

               hopefully now the loop is easier to read :)
            */
            while( _run )
            {

                _loopConnections();

            }

            trace( "selectserver: connections left [" + connections + "]" );
            _closeAndRemoveAllClients();

            trace( "shutting down server" );
            shutdown( serverfd, SHUT_RDWR );
            close( serverfd );

            exit( 0 );

        }

    }
}
