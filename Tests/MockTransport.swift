//
//  MockTransport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/28/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation
@testable import Starscream

public class MockTransport: Transport {
    
    public var usingTLS: Bool {
        return false
    }
    
    private weak var delegate: TransportEventClient?
    weak var server: MockServer?
    
    public init(server: MockServer) {
        self.server = server
    }
    
    public func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }
    
    public func connect(url: URL, timeout: Double) {
        server?.connect(client: self)
    }
    
    public func disconnect() {
        server?.disconnect(client: self)
    }
    
    public func write(data: Data, completion: @escaping ((Error?) -> ())) {
        server?.write(data: data, client: self)
    }
    
    public func received(data: Data) {
        delegate?.connectionChanged(state: .receive(data))
    }
    
    public func getSecurityData() -> SecurityData? {
        return nil
    }
}


public class MockSecurity: Security {
    
    public func isValid(data: SecurityData?) -> Bool {
        return true
    }
    
    public func validate(headers: [String: String], key: String) -> Error? {
        return nil
    }
}
