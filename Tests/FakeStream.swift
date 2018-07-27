//
//  FakeStream.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/26/18.
//  Copyright © 2018 Vluxe. All rights reserved.
//

import Foundation

class FakeStream: WSStream, TestServerDelegate {
    var delegate: WSStreamDelegate?
    let server: TestServer
    var buffer: Data?
    
    init(server: TestServer) {
        self.server = server
        self.server.delegate = self
    }
    
    func connect(url: URL, port: Int, timeout: TimeInterval, useSSL: Bool, completion: @escaping ((Error?) -> Void)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.server.start()
            completion(nil)
        })
    }
    
    func write(data: Data, completion: @escaping ((Error?) -> Void)) {
        server.receive(data: data)
    }
    
    func read() -> Data? {
        let data = buffer
        buffer = nil
        return data
    }
    
    func cleanup() {
        buffer = nil
    }
    
    func isValidSSLCertificate() -> Bool {
        return true
    }
    
    ///MARK: - TestServerDelegate
    func didSend(data: Data) {
        if buffer != nil {
            buffer?.append(data)
        } else {
            buffer = data
        }
    }
    
}
