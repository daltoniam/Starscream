//
//  HTTPHandler.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/24/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public enum HTTPUpgradeError: Error {
    case notAnUpgrade(Int)
    case invalidData
}

public struct HTTPWSHeader {
    static let upgradeName        = "Upgrade"
    static let upgradeValue       = "websocket"
    static let hostName           = "Host"
    static let connectionName     = "Connection"
    static let connectionValue    = "Upgrade"
    static let protocolName       = "Sec-WebSocket-Protocol"
    static let versionName        = "Sec-WebSocket-Version"
    static let versionValue       = "13"
    static let extensionName      = "Sec-WebSocket-Extensions"
    static let keyName            = "Sec-WebSocket-Key"
    static let originName         = "Origin"
    static let acceptName         = "Sec-WebSocket-Accept"
    static let switchProtocolCode = 101
    static let defaultSSLSchemes  = ["wss", "https"]
    
    /// Creates a new URLRequest based off the source URLRequest.
    /// - Parameter request: the request to "upgrade" the WebSocket request by adding headers.
    /// - Parameter supportsCompression: set if the client support text compression.
    /// - Parameter secKeyName: the security key to use in the WebSocket request. https://tools.ietf.org/html/rfc6455#section-1.3
    /// - returns: A URLRequest request to be converted to data and sent to the server.
    public static func createUpgrade(request: URLRequest, supportsCompression: Bool, secKeyName: String) -> URLRequest {
        guard let url = request.url, let host = url.host, let scheme = url.scheme else {
            return request
        }
        var port = url.port ?? 80
        if url.port == nil {
            if HTTPWSHeader.defaultSSLSchemes.contains(scheme) {
                port = 443
            } else {
                port = 80
            }
        }
        
        var req = request
        if request.value(forHTTPHeaderField: HTTPWSHeader.originName) == nil {
            if let url = request.url {
                var origin = url.absoluteString
                if let hostUrl = URL (string: "/", relativeTo: url) {
                    origin = hostUrl.absoluteString
                    origin.remove(at: origin.index(before: origin.endIndex))
                }
                req.setValue(origin, forHTTPHeaderField: HTTPWSHeader.originName)
            }
        }
        req.setValue(HTTPWSHeader.upgradeValue, forHTTPHeaderField: HTTPWSHeader.upgradeName)
        req.setValue(HTTPWSHeader.connectionValue, forHTTPHeaderField: HTTPWSHeader.connectionName)
        req.setValue(HTTPWSHeader.versionValue, forHTTPHeaderField: HTTPWSHeader.versionName)
        req.setValue(secKeyName, forHTTPHeaderField: HTTPWSHeader.keyName)
        
        if supportsCompression {
            let val = "permessage-deflate; client_max_window_bits; server_max_window_bits=15"
            req.setValue(val, forHTTPHeaderField: HTTPWSHeader.extensionName)
        }
        let hostValue = req.allHTTPHeaderFields?[HTTPWSHeader.hostName] ?? "\(host):\(port)"
        req.setValue(hostValue, forHTTPHeaderField: HTTPWSHeader.hostName)
        return req
    }
    
    // generateWebSocketKey 16 random characters between a-z and return them as a base64 string
    public static func generateWebSocketKey() -> String {
        return Data(bytes: (0..<16).map{ _ in UInt8.random(in: 97...122) }).base64EncodedString()
    }
}

public enum HTTPEvent {
    case success([String: String])
    case failure(Error)
}

public protocol HTTPHandlerDelegate: class {
    func didReceiveHTTP(event: HTTPEvent)
}

public protocol HTTPHandler {
    func register(delegate: HTTPHandlerDelegate)
    func convert(request: URLRequest) -> Data
    func parse(data: Data)
}
