//
//  TestServer.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/26/18.
//  Copyright © 2018 Vluxe. All rights reserved.
//

import Foundation

enum TestCase {
    case case1
    case case2
}

protocol TestServerDelegate: class {
    func didSend(data: Data)
}

class TestServer {
    var testCase: TestCase?
    weak var delegate: TestServerDelegate?
    var buffer = Data()
    var passed = false
    
    func start() {
        guard let testCase = testCase else { return }
        switch testCase {
        case .case1:
            case1()
        case .case2:
            break
        }
    }
    
    func receive(data: Data) {
        buffer.append(data)
    }
    
    func cleanup() {
        buffer = Data()
    }
    
    //MARK: - the cases!
    
    func case1() {
        //TODO: Websocket server framing
        //let data = "".data(using: .utf8)!
        //delegate?.didSend(data: frame)
    }
}
