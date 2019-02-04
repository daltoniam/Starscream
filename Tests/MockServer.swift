//
//  MockServer.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/29/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public class MockServer {
    public func connect(client: MockTransport) {
        //TODO: HTTP handshake here
    }
    
    public func disconnect(client: MockTransport) {
        //TODO: force disconnect
    }
    
    public func write(data: Data, client: MockTransport) {
        
    }
    
    public func write(data: Data) {
        
    }
}
