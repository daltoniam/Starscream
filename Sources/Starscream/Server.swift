//
//  Server.swift
//  Starscream
//
//  Created by Dalton Cherry on 4/2/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public enum ConnectionEvent {
    case connected([String: String])
    case disconnected(String, UInt16)
    case text(String)
    case binary(Data)
    case pong(Data?)
    case ping(Data?)
    case error(Error)
}

public protocol Connection {
    func write(data: Data, opcode: FrameOpCode)
}

public enum ServerEvent {
    case connected(Connection, [String: String])
    case disconnected(Connection, String, UInt16)
    case text(Connection, String)
    case binary(Connection, Data)
    case pong(Connection, Data?)
    case ping(Connection, Data?)
}

public protocol BaseServer {
    func start(address: String, port: Int)
}

public class Server: BaseServer {
    public var onEvent: ((ServerEvent) -> Void)?
    
    public func start(address: String, port: Int) {
        //TODO: setup listener
    }
}


