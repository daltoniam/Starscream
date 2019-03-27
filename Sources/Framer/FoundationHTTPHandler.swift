//
//  FoundationHTTPHandler.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/25/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public class FoundationHTTPHandler: HTTPHandler {

    var buffer = Data()
    weak var delegate: HTTPHandlerDelegate?
    
    public init() {
        
    }
    
    public func convert(request: URLRequest) -> Data {
        let msg = CFHTTPMessageCreateRequest(kCFAllocatorDefault, request.httpMethod! as CFString,
                                             request.url! as CFURL, kCFHTTPVersion1_1).takeRetainedValue()
        if let headers = request.allHTTPHeaderFields {
            for (aKey, aValue) in headers {
                CFHTTPMessageSetHeaderFieldValue(msg, aKey as CFString, aValue as CFString)
            }
        }
        if let body = request.httpBody {
            CFHTTPMessageSetBody(msg, body as CFData)
        }
        guard let data = CFHTTPMessageCopySerializedMessage(msg) else {
            return Data()
        }
        return data.takeRetainedValue() as Data
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

        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false).takeRetainedValue()
        if !CFHTTPMessageAppendBytes(response, pointer, data.count) {
            return false //not enough data, wait for more
        }
        if !CFHTTPMessageIsHeaderComplete(response) {
            return false //not enough data, wait for more
        }
        
        let code = CFHTTPMessageGetResponseStatusCode(response)
        if code != HTTPWSHeader.switchProtocolCode {
            delegate?.didReceiveHTTP(event: .failure(HTTPUpgradeError.notAnUpgrade(code)))
            return true
        }
        
        if let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response) {
            let nsHeaders = cfHeaders.takeRetainedValue() as NSDictionary
            var headers = [String: String]()
            for (key, value) in nsHeaders {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            delegate?.didReceiveHTTP(event: .success(headers))
            return true
        }
        
        delegate?.didReceiveHTTP(event: .failure(HTTPUpgradeError.invalidData))
        return true
    }
    
    public func register(delegate: HTTPHandlerDelegate) {
        self.delegate = delegate
    }
}
