//
//  FoundationTransport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public enum FoundationTransportError: Error {
    case invalidRequest
    case invalidOutputStream
}

public class FoundationTransport: NSObject, Transport, StreamDelegate {
    private weak var delegate: TransportEventClient?
    private let workQueue = DispatchQueue(label: "com.vluxe.starscream.websocket", attributes: [])
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
     public func connect(url: URL, timeout: Double = 10, isTLS: Bool = true) {
        guard let host = url.host, let port = url.port else {
            delegate?.connectionChanged(state: .failed(FoundationTransportError.invalidRequest))
            return
        }
        
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        let h = host as NSString
        CFStreamCreatePairWithSocketToHost(nil, h, UInt32(port), &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        guard let inStream = inputStream, let outStream = outputStream else {
                return
        }
        inStream.delegate = self
        outStream.delegate = self
        
        //TODO: all the stream configuration that can happen here...
        
        CFReadStreamSetDispatchQueue(inStream, workQueue)
        CFWriteStreamSetDispatchQueue(outStream, workQueue)
        inStream.open()
        outStream.open()
        
        //TODO: timeout support
    }
    
    public func disconnect() {

    }
    
    public func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }
    
    public func write(data: Data, completion: @escaping ((Error?) -> ())) {
        guard let outStream = outputStream else {
            completion(FoundationTransportError.invalidOutputStream)
            return
        }
        var total = 0
        let buffer = UnsafeRawPointer((data as NSData).bytes).assumingMemoryBound(to: UInt8.self)
        //NOTE: this might need to be dispatched to the work queue instead of being written inline. TBD.
        while total < data.count {
            let written = outStream.write(buffer, maxLength: data.count)
            if written < 0 {
                completion(FoundationTransportError.invalidOutputStream)
                return
            }
            total += written
        }
        completion(nil)
    }
    
    private func read() {
        guard let stream = inputStream else {
            return
        }
        let maxBuffer = 4096
        let buf = NSMutableData(capacity: maxBuffer)
        let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
        let length = stream.read(buffer, maxLength: maxBuffer)
        if length < 1 {
            return
        }
        let data = Data(bytes: buffer, count: length)
        delegate?.connectionChanged(state: .receive(data))
    }
    
    // MARK: - StreamDelegate
    
    open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .hasBytesAvailable {
            if aStream == inputStream {
                read()
            }
        } else if eventCode == .errorOccurred {
            delegate?.connectionChanged(state: .failed(aStream.streamError))
        } else if eventCode == .endEncountered {
            delegate?.connectionChanged(state: .cancelled)
        }
    }
}
