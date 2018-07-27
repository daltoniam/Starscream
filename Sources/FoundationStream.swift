//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  FoundationStream.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/23/18.
//  Copyright (c) 2014-2018 Dalton Cherry.
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

///
open class FoundationStream: NSObject, WSStream, StreamDelegate {
    private static let sharedWorkQueue = DispatchQueue(label: "com.vluxe.starscream.foundationstream", attributes: [])
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let security: FoundationSecurity
    public weak var delegate: WSStreamDelegate?
    let BUFFER_MAX = 4096
    var isConnected = false
    
    public var enableSOCKSProxy = false
    
    public init(security: FoundationSecurity = FoundationSecurity()) {
        self.security = security
    }
    
    public func connect(url: URL, port: Int, timeout: TimeInterval, useSSL: Bool, completion: @escaping ((Error?) -> Void)) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        let h = url.host! as NSString
        CFStreamCreatePairWithSocketToHost(nil, h, UInt32(port), &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        
        #if os(watchOS) //watchOS is unfortunately missing the kCFStream properties to make this work
        #else
        if enableSOCKSProxy {
            let proxyDict = CFNetworkCopySystemProxySettings()
            let socksConfig = CFDictionaryCreateMutableCopy(nil, 0, proxyDict!.takeRetainedValue())
            let propertyKey = CFStreamPropertyKey(rawValue: kCFStreamPropertySOCKSProxy)
            CFWriteStreamSetProperty(outputStream, propertyKey, socksConfig)
            CFReadStreamSetProperty(inputStream, propertyKey, socksConfig)
        }
        #endif
        
        guard let inStream = inputStream, let outStream = outputStream else { return }
        inStream.delegate = self
        outStream.delegate = self
    
        if useSSL, let error = security.configure(inputStream: inStream, outputStream: outStream) {
            completion(error)
            return
        }
        
        CFReadStreamSetDispatchQueue(inStream, FoundationStream.sharedWorkQueue)
        CFWriteStreamSetDispatchQueue(outStream, FoundationStream.sharedWorkQueue)
        inStream.open()
        outStream.open()
        isConnected = true
        
        var out = timeout// wait X seconds before giving up
        FoundationStream.sharedWorkQueue.async { [weak self] in
            while !outStream.hasSpaceAvailable {
                usleep(100) // wait until the socket is ready
                out -= 100
                if out < 0 {
                    completion(WSError(type: .writeTimeoutError, message: "Timed out waiting for the socket to be ready for a write", code: 0))
                    return
                } else if let error = outStream.streamError {
                    completion(error)
                    return // disconnectStream will be called.
                } else if self == nil {
                    completion(WSError(type: .closeError, message: "socket object has been dereferenced", code: 0))
                    return
                }
            }
            completion(nil) //success!
        }
    }
    
    public func write(data: Data, completion: @escaping ((Error?) -> Void)) {
        guard isConnected else {return} //don't write to a dead socket
        var written = 0
        let total = data.count
        while written < total {
            guard let outStream = outputStream else {
                completion(WSError(type: .outputStreamWriteError, message: "output stream had an error during write", code: 0))
                return
            }
            data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
                guard let buffer = UnsafeBufferPointer(start: pointer, count: total).fromOffset(written).baseAddress else {
                    completion(WSError(type: .outputStreamWriteError, message: "buffer error during write", code: 0))
                    return
                }
                written += outStream.write(buffer, maxLength: total - written)
                if written < 0 {
                    completion(WSError(type: .outputStreamWriteError, message: "buffer error during write", code: 0))
                    return
                }
            }
        }
        completion(nil)
    }
    
    /// read data from the stream.
    public func read() -> Data? {
        guard let stream = inputStream else {return nil}
        let buf = NSMutableData(capacity: BUFFER_MAX)
        let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
        let length = stream.read(buffer, maxLength: BUFFER_MAX)
        if length < 1 {
            return nil
        }
        return Data(bytes: buffer, count: length)
    }
    
    public func cleanup() {
        isConnected = false
        if let stream = inputStream {
            stream.delegate = nil
            CFReadStreamSetDispatchQueue(stream, nil)
            stream.close()
        }
        if let stream = outputStream {
            stream.delegate = nil
            CFWriteStreamSetDispatchQueue(stream, nil)
            stream.close()
        }
        outputStream = nil
        inputStream = nil
    }
    
    public func isValidSSLCertificate() -> Bool {
        guard let outputStream = outputStream else {return false} //the stream is already invalid
        return security.checkTrust(outputStream: outputStream)
    }
    
    /// MARK: - StreamDelegate
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .hasBytesAvailable {
            if aStream == inputStream {
                delegate?.newBytesInStream()
            }
        } else if eventCode == .errorOccurred {
            delegate?.streamDidError(error: aStream.streamError)
        } else if eventCode == .endEncountered {
            delegate?.streamDidError(error: nil)
        }
    }
}

