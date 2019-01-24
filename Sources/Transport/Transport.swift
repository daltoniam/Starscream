//
//  Transport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public enum ConnectionState {
    case connected
    case waiting
    case cancelled
    case failed(Error?)
    
    //the viability (connection status) of the connection has updated
    //e.g. connection is down, connection came back up, etc
    case viability(Bool)
    
    //the connection has upgrade to wifi from cellular.
    //you should consider reconnecting to take advantage of this
    case shouldReconnect(Bool)
    
    //the connection receive data
    case receive(Data)
}

public protocol TransportEventClient: class {
    func connectionChanged(state: ConnectionState)
}

public protocol Transport: class {
    func register(delegate: TransportEventClient)
    func connect(url: URL, timeout: Double, isTLS: Bool)
    func disconnect()
    func write(data: Data, completion: @escaping ((Error?) -> ()))
}
