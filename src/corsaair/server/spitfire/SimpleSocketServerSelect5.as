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
    
    import flash.system.Worker;
    import flash.system.WorkerDomain;
    import flash.concurrent.Mutex;

    /**
     * A simple socket server upgrade 5.
     * 
     * If you look back at the very first example
     * you will notcie that at that time we totally ignored
     * something named fork() in the C source code
     * 
     * fork() is a very convenient C function in the POSIX world
     * which allow to create a new process (child process)
     * that is an exact copy of the calling process (parent process)
     * see: http://pubs.opengroup.org/onlinepubs/9699919799/functions/fork.html
     * 
     * in server.c we can see
     * if (!fork()) { // this is the child process
     *      close(sockfd); // child doesn't need the listener
     *      if (send(new_fd, "Hello, world!", 13, 0) == -1)
     *          perror("send");
     *      close(new_fd);
     *      exit(0);
     *  }
     * 
     * In Redtamarin we deliberately decided to not support fork()
     * mainly because it works only with true POSIX systems
     * like Linux and Mac OS X but fail miserably under Windows
     * but also because we run our code inse a VM (AVM2)
     * and we can not as easily copy our process like that.
     *
     * But wait we have something as good as fork()
     * and which work everywhere, something called workers.
     * 
     * Here how we want tto manage it for now:
     * var server = new SimpleSocketServerSelect5();
     *     server.sleepTime = 1000;
     * 
     *     if( Worker.current.isPrimordial )
     *     {
     *         server.main();    
     *     }
     *     else
     *     {
     *         server.registerNewArrival();
     *     }
     * 
     * basically, if we are the server we want to run main()
     * and if we are a client connecting we want to run registerNewArrival()
     * 
     * But workers and fork() does not work exactly the same
     * even if a background worker will create a virtual copy of the VM (AVM2)
     * sharing data works differently.
     * 
     * The main point is to be able to extract the part thart is blocking forever
     * outside of the main process.
     * 
     * Here, our registration is something that can block forever
     * so for this part we want to run a worker so the worker will block
     * while our main server will not block.
     */
    public class SimpleSocketServerSelect5
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

        private var _mutex:Mutex;
        public var sharedData:ByteArray;

        public function SimpleSocketServerSelect5()
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
            sharedData  = new ByteArray();
            sharedData.shareable = true;
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


                //registerNewArrival( new_fd );

                /* Note:
                   It's here that we split the process
                   by creating a worker
                */
                trace( "setup worker and start it" );
                var newArrival:Worker = WorkerDomain.current.createWorkerFromPrimordial();
                    newArrival.setSharedProperty( "clientfd", new_fd );
                    newArrival.setSharedProperty( "mutex", _mutex );
                    newArrival.start();
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

        public function sharedTrace( message:String ):void
        {
            _mutex.lock();
            trace( message );
            _mutex.unlock();
        }

        public function getPrimordial():Worker
        {
            var wdomain:WorkerDomain = WorkerDomain.current;
            var workers:Vector.<Worker> = wdomain.listWorkers();
            var worker:Worker;
            for( var i:uint = 0; i < workers.length; i++ )
            {
                worker = workers[i];
                if( worker.isPrimordial )
                {
                    return worker;
                }
            }

            return null;
        }

        /**
         * Register a new connected client.
         */
        public function registerNewArrival():void
        {
            /* Note:
               Once we get our worker context
               we can obtain properties setup by the parent
               with getSharedProperty()

               be carefull here
               we use 2 workers
               - Worker.current: the current child or background worker
               - primordial: the parent or the primordial worker
            */
            var cworker:Worker = Worker.current;
            var primordial:Worker = getPrimordial();
            var clientfd:int  = cworker.getSharedProperty( "clientfd" );
            
            trace( "worker started" );
            trace( "worker.state = " + cworker.state );
            trace( "clientfd = " + clientfd );
            
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
               we can still do a timeout
               but this time it runs isolated in a worker
               so let make it big like 60 seconds
            */
            var timeA:uint = getTimer();
            var timeB:uint;
            var diff:uint  = 0;
            var timeout:uint = 60 * 1000; // 60 sec timeout
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
                        
                        /* Note:
                           We can not use
                           clients[ clientfd ].nickname = nickname;
                           because the current var 'clients' is handled by the server
                           but we can use a little trick to set a shared property on the
                           primoridal worker (eg. the server)
                        */
                        primordial.setSharedProperty( "nickname" + clientfd  , nickname );
                        
                        trace( "selectserver: socket " + clientfd + " registered as " + nickname );
                        break;
                    }

                }
            }

            trace( "selectserver: terminating worker" );
            var terminated:Boolean = cworker.terminate();
            trace( "selectserver: terminated = " + terminated );
        }

        private function _checkRegistration():void
        {
            /* Note:
               This can be run only from the server context
               because we need to access the 'childs' property

               and basically we use a stupid trick
               we loop trough all the connections
               to obtai nthe socket descriptor (we use it as an ID)
               and then we check the primordial worker shared property
               to see if a child has defined a nickname there

               eg.
               Server
                 |_ childs[7].nickname = ""
                => worker: 
                  primordial.setSharedProperty( "nickname7", "the nickname chosen" );
                => server loop
                  nickname = primordial.getSharedProperty( "nickname7" )
                  if not empty
                  childs[7].nickname = nickname

               yes, we have no events or promises and it is a bit of a pain
               to exchange data with the workers
            */
            var primordial:Worker = Worker.current;

            for( var i:uint = 0; i < connections.length; i++ )
            {
                var clientfd:uint = connections[i];
                if( clients[clientfd].nickname == "" )
                {
                    var nickname:String = primordial.getSharedProperty( "nickname" + clientfd );
                    if( (nickname != undefined) &&
                        (nickname != 'null') &&
                        (nickname != "") )
                    {
                        clients[clientfd].nickname = nickname;
                    }
                }
            }

        }

        public function main():void
        {
            _mutex = new Mutex();

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
                trace( "connections = " + connections.length );

                // check for new registrations
                _checkRegistration();

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
