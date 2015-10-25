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
    
    import flash.utils.getTimer;
    import flash.utils.ByteArray;
    import flash.utils.Dictionary;
    

    /**
     * A simple socket server upgrade 4.
     * 
     * OK our client registration is blocking and that's bad
     * let's see how we can add a timeout.
     */
    public class SimpleSocketServerSelect4
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

        public var clients:Dictionary; // list of clients informations
        public var sleepTime:uint; // time is expressed in milliseconds

        public function SimpleSocketServerSelect4()
        {
            super();

            _address    = [];
            _info       = null;
            _run        = true;
            serverfd    = -1;
            selected    = -1;
            connections = [];
            clients     = new Dictionary();
            sleepTime   = 0; // 0 means "do not sleep"
        }

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
                _addClient( new_fd );
                
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


                registerNewArrival( new_fd );
            }
        }

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

                if( clients[selected].nickname != "" )
                {
                    trace( clients[selected].nickname + " : " + msg_in );
                }
                else
                {
                    trace( selected + " : " + msg_in );
                }
                

                if( msg_in == "shutdown" )
                {
                    trace( "selectserver: received 'shutdown' command" );
                    _run = false;
                }
            }
        }

        private function _addClient( sd:int, name:String = "" ):void
        {
            connections.push( sd );
            clients[ sd ] = { nickname: name };
        }

        private function _removeClient( sd:int ):void
        {
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
                    delete clients[ sd ];
                }
            }
        }

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

                if( clients[desc].nickname != "" )
                {
                    trace( "selectserver: terminate " + clients[desc].nickname + " (" + desc + ")" );
                }
                else
                {
                    trace( "selectserver: terminate " + desc );    
                }
                
                close( desc );              // close the socket
                connections.splice( i, 1 ); // remove the socket from the connections list
                delete clients[desc];       // delete the socket key for the clients data
                i = 0; //rewind
            }
        }

        /**
         * Register a new connected client.
         */
        public function registerNewArrival( clientfd:int ):void
        {

            var msg_welcome:String = "What is your nickname?\n";
            var bytes_welcome:ByteArray = new ByteArray();
                bytes_welcome.writeUTFBytes( msg_welcome );
                bytes_welcome.position = 0;
            var welcome:int = send( clientfd, bytes_welcome );
            if( welcome == -1 )
            {
                trace( "selectserver: welcome sent" );
                trace( new CError( "", errno ) );
                close( clientfd );
                _removeClient( clientfd );
                return;
            }

            trace( "selectserver: wait for nickname ..." );
            var bytes_answer:ByteArray = new ByteArray();
            var nickname:String;
            var n:int;

            /* Note:
               Because we are inside an infinite loop
               and recv() is blocking the server will be stuck forever
               here how to add a timeout

               It's not perfect but at least it allow you to not wait forever
               but note also as soon as there are data in the pipe
               eg. isReadable() returns true
               if someone processing the data take forever
               it will block also forever your loop
               
               what we really need is concurrency
               see next example :)
            */
            var timeA:uint = getTimer();
            var timeB:uint;
            var diff:uint  = 0;
            var timeout:uint = 5 * 1000; // 5 sec timeout
            while( true )
            {
                timeB = getTimer();
                diff  = timeB - timeA;
                if( diff > timeout )
                {
                    trace( "selectserver: socket " + clientfd + " timed out" );
                    var bytes_bye:ByteArray = new ByteArray();
                        bytes_bye.writeUTFBytes( "You have been disconnected, bye\n" );
                    send( clientfd, bytes_bye );
                    close( clientfd );
                    _removeClient( clientfd );
                    break;
                }

                // only process if there is data in the pipe
                if( isReadable(clientfd) )
                {

                    n = recv( clientfd, bytes_answer );
                    if( n <= 0 )
                    {
                        // got error or connection closed by client
                        if( n == 0 )
                        {
                            // connection closed
                            trace( "selectserver: socket " + clientfd + " hung up" );
                        }
                        else
                        {
                            trace( "recv" );
                            trace( new CError( "", errno ) );
                        }

                        close( clientfd );
                        _removeClient( clientfd );
                        break;
                    }
                    else
                    {
                        bytes_answer.position = 0;
                        nickname = bytes_answer.readUTFBytes( n );
                        nickname = nickname.split( "\n" ).join( "" );
                        clients[ clientfd ].nickname = nickname;

                        trace( "selectserver: socket " + clientfd + " registered as " + nickname );
                        break;
                    }

                }
            }
        }

        public function main():void
        {
            serverfd = _getBindingSocket();

            if( _info == null )
            {
                trace( "selectserver: failed to bind" );
                exit( 1 );
            }

            var listening:int = listen( serverfd, BACKLOG );
            if( listening == -1 )
            {
                trace( "listen" );
                trace( new CError( "", errno ) );
                exit( 1 );
            }

            trace( "selectserver: waiting for connections..." );

            // the server is always the first client to be added to the connections
            _addClient( serverfd, "server" );
            trace( "selectserver: server on socket " + serverfd );

            var frame:uint = 0;

            // main server loop
            while( _run )
            {
                //trace( "selectserver: main loop" );
                trace( "selectserver: main loop " + frame++ );

                _loopConnections();

                if( sleepTime > 0 )
                {
                    sleep( sleepTime );
                }
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
