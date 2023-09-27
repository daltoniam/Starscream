//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Transport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
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

public enum ConnectionState {
    /// Ready connections can send and receive data
    case connected
    
    /// Waiting connections have not yet been started, or do not have a viable network
    case waiting
    
    /// Cancelled connections have been invalidated by the client and will send no more events
    case cancelled
    
    /// Failed connections are disconnected and can no longer send or receive data
    case failed(Error?)
    
    /// Viability (connection status) of the connection has updated
    /// e.g. connection is down, connection came back up, etc.
    case viability(Bool)
    
    /// Connection ca be upgraded to wifi from cellular.
    /// You should consider reconnecting to take advantage of this.
    case shouldReconnect(Bool)
    
    /// Received data
    case receive(Data)
    
    /// Remote peer has closed the network connection.
    case peerClosed
}

public protocol TransportEventClient: AnyObject {
    func connectionChanged(state: ConnectionState)
}

public protocol Transport: AnyObject {
    func register(delegate: TransportEventClient)
    func connect(url: URL, timeout: Double, certificatePinning: CertificatePinning?)
    func disconnect()
    func write(data: Data, completion: @escaping ((Error?) -> ()))
    var usingTLS: Bool { get }
}
