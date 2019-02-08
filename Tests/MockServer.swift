//
//  MockServer.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/29/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public class MockServer {
    var didUpgrade = false
    var client: MockTransport?
    public func connect(client: MockTransport) {
        self.client = client
        didUpgrade = false
        //TODO: save client and notice it isn't upgrade
    }
    
    public func disconnect(client: MockTransport) {
        //TODO: force disconnect
        didUpgrade = false
    }
    
    public func write(data: Data, client: MockTransport) {
        //TODO:
        // 1. handle HTTP request and set didUpgrade flag
        // 2. send back HTTP response
        // 3. handle websocket frames as they comes in
        // 4. have an expectations of results
        // 5. "timeout" on failure
    }
    
    public func write(data: Data) {
        
    }
}
