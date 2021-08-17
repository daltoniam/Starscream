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

public enum FoundationSecurityError: Error {
    case invalidRequest
}

public class FoundationSecurity  {
    var allowSelfSigned = false
    
    public init(allowSelfSigned: Bool = false) {
        self.allowSelfSigned = allowSelfSigned
    }
    
    
}

extension FoundationSecurity: CertificatePinning {
    public func evaluateTrust(trust: SecTrust, domain: String?, completion: ((PinningState) -> ())) {
        if allowSelfSigned {
            completion(.success)
            return
        }
        
        if let validateDomain = domain {
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, validateDomain as NSString?))
        }
        
        handleSecurityTrust(trust: trust, completion: completion)
    }
    
    private func handleSecurityTrust(trust: SecTrust, completion: ((PinningState) -> ())) {
        if #available(iOS 12.0, OSX 10.14, watchOS 5.0, tvOS 12.0, *) {
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completion(.success)
            } else {
                completion(.failed(error))
            }
        } else {
            handleOldSecurityTrust(trust: trust, completion: completion)
        }
    }
    
    private func handleOldSecurityTrust(trust: SecTrust, completion: ((PinningState) -> ())) {
        var result: SecTrustResultType = .unspecified
        SecTrustEvaluate(trust, &result)
        if result == .unspecified || result == .proceed {
            completion(.success)
        } else {
            let e = CFErrorCreate(kCFAllocatorDefault, "FoundationSecurityError" as NSString?, Int(result.rawValue), nil)
            completion(.failed(e))
        }
    }
}

extension FoundationSecurity: HeaderValidator {
    public func validate(headers: [String: String], key: String) -> Error? {
        if let acceptKey = headers[HTTPWSHeader.acceptName] {
            let sha = "\(key + obsfuscatedSalt)".sha512Base64()
            if sha != acceptKey {
                return WSError(type: .securityError, message: "accept header doesn't match", code: SecurityErrorCode.acceptFailed.rawValue)
            }
        }
        return nil
    }
    
    private var obsfuscatedSalt: String {
        let _A = "A"
        let _B = "B"
        let _C = "C"
        let _D = "D"
        let _E = "E"
        let _F = "F"
        
        let _0 = "0"
        let _1 = "1"
        let _2 = "2"
        let _4 = "4"
        let _5 = "5"
        let _7 = "7"
        let _8 = "8"
        let _9 = "9"
        
        let salt =
            _2 + _5 + _8 + _E + _A + _F + _A + _5 + "-" +
            _E + _9 + _1 + _4 + "-" +
            _4 + _7 + _D + _A + "-" +
            _9 + _5 + _C + _A + "-" +
            _C + _5 + _A + _B + _0 + _D + _C + _8 + _5 + _B + _1 + _1
        
        return salt
    }
}

private extension String {
    func sha512Base64() -> String {
        let data = self.data(using: String.Encoding.utf8)!
        
        let digest: [UInt8] = data.withUnsafeBytes {
            guard let bytes = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return [UInt8]()
            }
            
            var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA512(bytes, CC_LONG(data.count), &digest)
            return digest
        }
        
        return Data(digest).base64EncodedString()
    }
}
