//
//  ClientCertificate.swift
//  Starscream
//
//  Created by Tomasz Trela on 08/03/2018.
//  Copyright © 2018 Vluxe. All rights reserved.
//

import Foundation

public class SSLClientCertificate {
    internal let streamSSLCertificates: NSArray

    /**
     Convenience init.
     - parameter pkcs12Path: Path to pkcs12 file containing private key and X.509 ceritifacte (.p12)
     - parameter password: file password, see **kSecImportExportPassphrase**
     */
    public convenience init?(pkcs12Path: String, password: String) {
        let pkcs12Url = URL(fileURLWithPath: pkcs12Path)
        self.init(pkcs12Url: pkcs12Url, password: password)
    }
    
    /**
     Convenience init. For more information, see SSLSetCertificate() in Security/SecureTransport.h.
     - parameter identity: SecIdentityRef, see **kCFStreamSSLCertificates**
     - parameter identityCertificate: CFArray of SecCertificateRefs, see **kCFStreamSSLCertificates**
     */
    public init(identity: SecIdentity, identityCertificate: SecCertificate) {
        self.streamSSLCertificates = NSArray(objects: identity, identityCertificate)
    }
    
    /**
     Convenience init.
     - parameter pkcs12Url: URL to pkcs12 file containing private key and X.509 ceritifacte (.p12)
     - parameter password: file password, see **kSecImportExportPassphrase**
     */
    public convenience init?(pkcs12Url: URL, password: String) {
        let importOptions = [kSecImportExportPassphrase as String : password] as CFDictionary
        self.init(pkcs12Url: pkcs12Url, importOptions: importOptions)
    }
    
    /**
     Designated init.
     - parameter pkcs12Url: URL to pkcs12 file containing private key and X.509 ceritifacte (.p12)
     - parameter importOptions: A dictionary containing import options. A
     kSecImportExportPassphrase entry is required at minimum. Only password-based
     PKCS12 blobs are currently supported. See **SecImportExport.h**
     */
    public init?(pkcs12Url: URL, importOptions: CFDictionary) {
        do {
            let pkcs12Data = try Data(contentsOf: pkcs12Url)
            var rawIdentitiesAndCertificates: CFArray?
            let pkcs12CFData: CFData = pkcs12Data as CFData
            let importStatus = SecPKCS12Import(pkcs12CFData, importOptions, &rawIdentitiesAndCertificates)
            
            guard importStatus == errSecSuccess else {
                print("(Starscream) Error during 'SecPKCS12Import', see 'SecBase.h' - OSStatus: \(importStatus)")
                return nil
            }
            guard let identitiyAndCertificate = (rawIdentitiesAndCertificates as? Array<Dictionary<String, Any>>)?.first else {
                print("(Starscream) Error - PKCS12 file is empty")
                return nil
            }
            
            let identity = identitiyAndCertificate[kSecImportItemIdentity as String] as! SecIdentity
            var identityCertificate: SecCertificate?
            let copyStatus = SecIdentityCopyCertificate(identity, &identityCertificate)
            guard copyStatus == errSecSuccess else {
                print("(Starscream) Error during 'SecIdentityCopyCertificate', see 'SecBase.h' - OSStatus: \(copyStatus)")
                return nil
            }
            self.streamSSLCertificates = NSArray(objects: identity, identityCertificate!)
        } catch {
            print("(Starscream) Error during creating Data from URL - \(error)")
            return nil
        }
    }
}

