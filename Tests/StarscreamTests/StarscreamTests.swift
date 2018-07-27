//
//  StarscreamTests.swift
//  StarscreamTests
//
//  Created by Austin Cherry on 9/25/14.
//  Copyright (c) 2014 Vluxe. All rights reserved.
//

import XCTest

class StarscreamTests: XCTestCase {
    
    var socket: WebSocket!
    let testServer = TestServer()
    override func setUp() {
        super.setUp()
        let url = URL(string: "http://fakedomain.com")! //not a real request
        let req = URLRequest(url: url)
        let fakeStream = FakeStream(server: testServer)
        socket = WebSocket(request: req, protocols: nil, stream: fakeStream)
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func runSocket() {
        socket.onText = { [weak self] (text: String) in
            self?.socket.write(string: text)
        }
        socket.onData = { [weak self] (data: Data) in
            self?.socket.write(data: data)
        }
        var once = false
        socket.onDisconnect = {[weak self] (error: Error?) in
            if !once {
                once = true
                let status = self?.testServer.passed ?? false
                if status {
                    XCTAssert(true, "Pass")
                } else {
                    XCTAssert(false, "Failed")
                }
            }
        }
        socket.connect()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        XCTAssert(true, "Pass")
    }
    
//    func testCase1() {
//        testServer.testCase = .case1
//        runSocket()
//    }
    

    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
