//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  NetworkStream.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/23/18.
//  Copyright (c) 2014-2018 Dalton Cherry.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation
#if canImport(Network)
import Network
#endif

/// Implementation of the Network framework that was introduced in iOS 12/MacOS 10.14.
/// This class will probably replace the Foundation one in the future, but because Foundation is battle-tested
/// it will continue to be provided for backwards compatibility reasons.
@available(iOS 12.0, *)
@available(iOSApplicationExtension 12.0, tvOSApplicationExtension 12.0, OSXApplicationExtension 10.14, *)
open class NetworkStream: WSStream {
    public weak var delegate: WSStreamDelegate?
    private var stream: NWConnection?
    private static let sharedWorkQueue = DispatchQueue(label: "com.vluxe.starscream.networkstream", attributes: [])
    private var readQueue = [Data]()
    var running = false
    var connected = false
    
    //need security stuff
    public init() {
        
    }
    
    /// connect to the websocket server and start the read loop
    public func connect(url: URL, port: Int, timeout: TimeInterval, useSSL: Bool, completion: @escaping ((Error?) -> Void)) {
        let parameters: NWParameters = useSSL ? .tls : .tcp
        let conn = NWConnection(host: NWEndpoint.Host.name(url.host!, nil), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)
        connected = false
        func doConnect(_ error: Error?) {
            if !connected {
                completion(error)
                connected = true
                running = true
            } else {
                running = false
            }
        }
        conn.stateUpdateHandler = { [weak self] (newState) in
            switch newState {
            case .ready:
                doConnect(nil)
            case .waiting:
                self?.delegate?.streamIsWaitingForConnectivity()
            case .cancelled:
                doConnect(nil)
            case .failed(let error):
                doConnect(error)
                self?.delegate?.streamDidError(error: error)
            case .setup, .preparing:
                break
            }
        }

        conn.viabilityUpdateHandler = { [weak self] (isViable) in
            self?.delegate?.streamPathViabilityUpdate(isViable: isViable)
        }

        conn.betterPathUpdateHandler = { [weak self] (isBetter) in
            self?.delegate?.streamBetterPathUpdate(isBetter: isBetter)
        }

        conn.start(queue: NetworkStream.sharedWorkQueue)
        stream = conn
        running = true
        readLoop()
    }
    
    /// Write data over the socket to the websocket server
    /// From how I understand the documentation for send, we might need to optimize with queued writes.
    public func write(data: Data, completion: @escaping ((Error?) -> Void)) {
        stream?.send(content: data, completion: .contentProcessed { (sendError) in
            completion(nil) //sendError
        })
    }
    
    /// get hte latest message from the read queue
    public func read() -> Data? {
        return readQueue.removeFirst()
    }
    
    /// stream isn't to be used anymore
    public func cleanup() {
        running = false
        stream?.cancel()
    }
    
    public func isValidSSLCertificate() -> Bool {
        return true //return true until SSL Pinning is done, this enables WSS
        //return false //TODO: SSL pinning for the network framework
    }
    
    //continually read from the stream waiting for more content to process
    func readLoop() {
        if !running {
            return
        }
        stream?.receive(minimumIncompleteLength: 2, maximumLength: 4096, completion: {[weak self] (data, context, isComplete, error) in
            guard let s = self else {return}
            if let err = error {
                s.delegate?.streamDidError(error: err)
                return
            }
            if let data = data {
                s.readQueue.append(data)
                s.delegate?.newBytesInStream()
            }
            // I'm not sure why this is needed (might be a bug),
            // but this indicates the stream is "dead" and should be closed
            // even though we never got that state update
            if isComplete && data == nil, context == nil, error == nil {
                s.delegate?.streamDidError(error: nil)
                s.cleanup()
                return
            }
            s.readLoop()
        })
        
    }
    
}
