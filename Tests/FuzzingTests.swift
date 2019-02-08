//
//  FuzzingTests.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/28/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import XCTest
@testable import Starscream

class FuzzingTests: XCTestCase {
    
    var websocket: WebSocketNew!
    var server: MockServer!
    
    override func setUp() {
        super.setUp()
        let url = URL(string: "http://vluxe.io/ws")! //domain doesn't matter with the mock transport
        let request = URLRequest(url: url)
        let s = MockServer()
        let transport = MockTransport(server: s)
        websocket = WebSocketNew(request: request, transport: transport)
        server = s
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func runWebsocket(serverAction: @escaping (() -> Void)) {
        websocket.onEvent = { event in
            switch event {
            case .text(let string):
                self.websocket.write(string: string)
            case .binary(let data):
                self.websocket.write(data: data)
            case .ping(let data):
                break
            case .pong(let data):
                break
            case .connected(let headers):
                serverAction()
            case .disconnected(_):
                break
            case .error(_):
                break
            }
        }
        websocket.connect()
        
    }
    
    func testCase1() {
        runWebsocket {
            let payload = "".data(using: .utf8)!
            self.server.write(data: payload)
        }
        //TODO: ask server if expected response matches
        //TODO: disconnect gracefully
    }
}
