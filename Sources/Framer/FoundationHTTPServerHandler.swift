//
//  FoundationHTTPServerHandler.swift
//  Starscream
//
//  Created by Dalton Cherry on 4/2/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public class FoundationHTTPServerHandler: HTTPServerHandler {
    var buffer = Data()
    weak var delegate: HTTPServerDelegate?
    let getVerb: NSString = "GET"
    
    public func register(delegate: HTTPServerDelegate) {
        self.delegate = delegate
    }
    
    public func createResponse(headers: [String: String]) -> Data {
        let response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, HTTPWSHeader.switchProtocolCode,
                                                   nil, kCFHTTPVersion1_1).takeRetainedValue()
        
        //TODO: add other values to make a proper response here...
        //TODO: also sec key thing (Sec-WebSocket-Key)
        for (key, value) in headers {
            CFHTTPMessageSetHeaderFieldValue(response, key as CFString, value as CFString)
        }
        guard let cfData = CFHTTPMessageCopySerializedMessage(response)?.takeRetainedValue() else {
            return Data()
        }
        return cfData as Data
    }
    
    public func parse(data: Data) {
        buffer.append(data)
        if parseContent(data: buffer) {
            buffer = Data()
        }
    }
    
    //returns true when the buffer should be cleared
    func parseContent(data: Data) -> Bool {
        var pointer = [UInt8]()
        data.withUnsafeBytes { pointer.append(contentsOf: $0) }
        
        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeRetainedValue()
        if !CFHTTPMessageAppendBytes(response, pointer, data.count) {
            return false //not enough data, wait for more
        }
        if !CFHTTPMessageIsHeaderComplete(response) {
            return false //not enough data, wait for more
        }
        if let method = CFHTTPMessageCopyRequestMethod(response)?.takeRetainedValue() {
            if method != getVerb {
                delegate?.didReceive(event: .failure(HTTPUpgradeError.invalidData))
                return true
            }
        }
        
        if let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response) {
            let nsHeaders = cfHeaders.takeRetainedValue() as NSDictionary
            var headers = [String: String]()
            for (key, value) in nsHeaders {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            delegate?.didReceive(event: .success(headers))
            return true
        }
        
        delegate?.didReceive(event: .failure(HTTPUpgradeError.invalidData))
        return true
    }
}
