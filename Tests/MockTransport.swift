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
    
    private let id: String
    weak var server: MockServer?
    var uuid: String {
        return id
    }
    
    public init(server: MockServer) {
        self.server = server
        self.id = UUID().uuidString
    }
    
    public func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }
    
    public func connect(url: URL, timeout: Double) {
        server?.connect(transport: self)
        delegate?.connectionChanged(state: .connected)
    }
    
    public func disconnect() {
        server?.disconnect(uuid: uuid)
    }
    
    public func write(data: Data, completion: @escaping ((Error?) -> ())) {
        server?.write(data: data, uuid: uuid)
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
