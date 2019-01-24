//
//  HTTPHandler.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/24/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public enum HTTPEvent {
    case success([String: String])
    case failure(Error)
}

public protocol HTTPHandlerDelegate: class {
    func didReceiveHTTP(event: HTTPEvent)
}

public protocol HTTPHandler {
    func register(delegate: HTTPHandlerDelegate)
    func createUpgrade(request: URLRequest) -> Data
    func parse(data: Data)
}

public class FoundationHTTPHandler: HTTPHandler {
    weak var delegate: HTTPHandlerDelegate?
    
    public func createUpgrade(request: URLRequest) -> Data {
        return Data()
    }
    
    public func parse(data: Data) {
        
    }
    
    public func register(delegate: HTTPHandlerDelegate) {
        self.delegate = delegate
    }
}
