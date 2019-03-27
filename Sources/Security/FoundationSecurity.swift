//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  FoundationSecurity.swift
//  Starscream
//
//  Created by Dalton Cherry on 3/16/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation
import CommonCrypto

public struct FoundationSecurityData: SecurityData {
    let trust: SecTrust?
    let domain: String?
}

public class FoundationSecurity: Security {

    //TODO: init method that loads SSL certifcates!
    var certs = [Data]()
    
    // validates the stream is connected to the expected server using SSL pinning
    public func isValid(data: SecurityData?) -> Bool {
        if certs.count == 0 {
            return true //no certs to validated with, so allow pinning to go through
        }
        guard let data = data else {
            return false //TODO: default is to pass or fail?
        }
        if data is FoundationSecurityData {
            //TODO: do SSL pinning check here
            return true
        }
        return false
    }
    
    // validates the "Sec-WebSocket-Accept" header as defined 1.3 of the RFC 6455
    // https://tools.ietf.org/html/rfc6455#section-1.3
    public func validate(headers: [String: String], key: String) -> Error? {
        if let acceptKey = headers[HTTPWSHeader.acceptName.lowercased()] {
            let sha = "\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".sha1Base64()
            if sha != acceptKey {
                return WSError(type: .securityError, message: "accept header doesn't match", code: SecurityErrorCode.acceptFailed.rawValue)
            }
        }
        return nil
    }
}

private extension String {
    func sha1Base64() -> String {
        let data = self.data(using: .utf8)!
        let pointer = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
            return digest
        }
        return Data(pointer).base64EncodedString()
    }
}
