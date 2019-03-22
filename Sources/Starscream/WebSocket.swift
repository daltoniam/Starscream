//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//  Copyright (c) 2014-2019 Dalton Cherry.
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

public enum ErrorType: Error {
    case compressionError
    case securityError
    case protocolError //There was an error parsing the WebSocket frames
}

public struct WSError: Error {
    public let type: ErrorType
    public let message: String
    public let code: Int
}

public protocol WebSocketClient: class {
    func connect()
    func disconnect(closeCode: UInt16)
    func write(string: String, completion: (() -> ())?)
    func write(stringData: Data, completion: (() -> ())?)
    func write(data: Data, completion: (() -> ())?)
    func write(ping: Data, completion: (() -> ())?)
    func write(pong: Data, completion: (() -> ())?)
}

//implements some of the base behaviors
extension WebSocketClient {
    public func write(string: String) {
        write(string: string, completion: nil)
    }
    
    public func write(data: Data) {
        write(data: data, completion: nil)
    }
    
    public func write(ping: Data) {
        write(ping: ping, completion: nil)
    }
    
    public func write(pong: Data) {
        write(pong: pong, completion: nil)
    }
    
    public func disconnect() {
        disconnect(closeCode: CloseCode.normal.rawValue)
    }
}

public enum WebSocketEvent {
    case connected([String: String])
    case disconnected(String, UInt16)
    case text(String)
    case binary(Data)
    case pong(Data?)
    case ping(Data?)
    case error(Error?)
    case viablityChanged(Bool)
    case reconnectSuggested(Bool)
    case cancelled
}

public protocol WebSocketDelegate: class {
    func didReceive(event: WebSocketEvent, client: WebSocket)
}

open class WebSocket: WebSocketClient, TransportEventClient, FramerEventClient,
FrameCollectorDelegate, HTTPHandlerDelegate {
    private let transport: Transport
    private let framer: Framer
    private let httpHandler: HTTPHandler
    private let compressionHandler: CompressionHandler?
    private let secHandler: Security
    private let frameHandler = FrameCollector()
    private var didUpgrade = false
    private var secKeyValue = ""
    
    public weak var delegate: WebSocketDelegate?
    public var onEvent: ((WebSocketEvent) -> Void)?
    
    public var request: URLRequest
    // Where the callback is executed. It defaults to the main UI thread queue.
    public var callbackQueue = DispatchQueue.main
    
    // serial write queue to ensure writes happen in order
    private let writeQueue = DispatchQueue(label: "com.vluxe.starscream.writequeue")
    private var canSend = false
    private let mutex = DispatchSemaphore(value: 1)
    
    public init(request: URLRequest, transport: Transport, security: Security,
                httpHandler: HTTPHandler = FoundationHTTPHandler(),
                framer: Framer = WSFramer(),
                compressionHandler: CompressionHandler? = nil) {
        self.request = request
        self.transport = transport
        self.framer = framer
        self.httpHandler = httpHandler
        self.secHandler = security
        self.compressionHandler = compressionHandler
        framer.updateCompression(supports: compressionHandler != nil)
        frameHandler.delegate = self
    }
    
    public convenience init(request: URLRequest) {
        if #available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            self.init(request: request, transport: TCPTransport(), security: FoundationSecurity())
        } else {
            self.init(request: request, transport: FoundationTransport(), security: FoundationSecurity())
        }
    }
    
    public func connect() {
        mutex.wait()
        let isConnected = canSend
        mutex.signal()
        if isConnected {
            return
        }
        
        transport.register(delegate: self)
        framer.register(delegate: self)
        httpHandler.register(delegate: self)
        frameHandler.delegate = self
        guard let url = request.url else {
            return
        }
        var isTLS = false
        if let scheme = url.scheme, HTTPWSHeader.defaultSSLSchemes.contains(scheme) {
            isTLS = true
        }
        transport.connect(url: url, timeout: request.timeoutInterval, isTLS: isTLS)
    }
    
    public func disconnect(closeCode: UInt16 = CloseCode.normal.rawValue) {
        let capacity = MemoryLayout<UInt16>.size
        var pointer = Data(capacity: capacity).withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: capacity))
        }
        writeUint16(&pointer, offset: 0, value: closeCode)
        let payload = Data(bytes: pointer, count: MemoryLayout<UInt16>.size)
        write(data: payload, opcode: .connectionClose, completion: nil)
    }
    
    
    public func forceDisconnect() {
        transport.disconnect()
    }
    
    public func write(data: Data, completion: (() -> ())?) {
         write(data: data, opcode: .binaryFrame, completion: completion)
    }
    
    public func write(string: String, completion: (() -> ())?) {
        let data = string.data(using: .utf8)!
        write(data: data, opcode: .textFrame, completion: completion)
    }
    
    public func write(stringData: Data, completion: (() -> ())?) {
        write(data: stringData, opcode: .textFrame, completion: completion)
    }
    
    public func write(ping: Data, completion: (() -> ())?) {
        write(data: ping, opcode: .ping, completion: completion)
    }
    
    public func write(pong: Data, completion: (() -> ())?) {
        write(data: pong, opcode: .pong, completion: completion)
    }
    
    private func write(data: Data, opcode: FrameOpCode, completion: (() -> ())?) {
        writeQueue.async { [weak self] in
            guard let s = self else { return }
            s.mutex.wait()
            let canWrite = s.canSend
            s.mutex.signal()
            if !canWrite {
                return
            }
            
            var isCompressed = false
            var sendData = data
            if let compressedData = s.compressionHandler?.compress(data: data) {
                sendData = compressedData
                isCompressed = true
            }
            
            let frameData = s.framer.createWriteFrame(opcode: opcode, payload: sendData, isCompressed: isCompressed)
            s.transport.write(data: frameData, completion: {_ in
                completion?()
            })
        }
    }
    
    // MARK: - TransportEventClient
    
    public func connectionChanged(state: ConnectionState) {
        switch state {
        case .connected:
            if !secHandler.isValid(data: transport.getSecurityData()) {
                let error = WSError(type: .securityError, message: "ssl pinning host doesn't match", code: SecurityErrorCode.pinningFailed.rawValue)
                handleError(error)
                return
            }
            secKeyValue = HTTPWSHeader.generateWebSocketKey()
            let wsReq = HTTPWSHeader.createUpgrade(request: request, supportsCompression: framer.supportsCompression(), secKeyValue: secKeyValue)
            let data = httpHandler.convert(request: wsReq)
            transport.write(data: data, completion: {_ in })
        case .waiting:
            break
        case .failed(let error):
            handleError(error)
        case .viability(let isViable):
            broadcast(event: .viablityChanged(isViable))
        case .shouldReconnect(let status):
            broadcast(event: .reconnectSuggested(status))
        case .receive(let data):
            if didUpgrade {
                framer.add(data: data)
            } else {
                httpHandler.parse(data: data)
            }
        case .cancelled:
            broadcast(event: .cancelled)
        }
    }
    
    // MARK: - HTTPHandlerDelegate
    
    public func didReceiveHTTP(event: HTTPEvent) {
        switch event {
        case .success(let headers):
            if let error = secHandler.validate(headers: headers, key: secKeyValue) {
                handleError(error)
                return
            }
            mutex.wait()
            didUpgrade = true
            canSend = true
            mutex.signal()
            compressionHandler?.load(headers: headers)
            broadcast(event: .connected(headers))
        case .failure(let error):
            handleError(error)
        }
    }
    
    // MARK: - FramerEventClient
    
    public func frameProcessed(event: FrameEvent) {
        switch event {
        case .frame(let frame):
            frameHandler.add(frame: frame)
        case .error(let error):
            handleError(error)
        }
    }
    
    // MARK: - FrameCollectorDelegate
    
    public func decompress(data: Data, isFinal: Bool) -> Data? {
        return compressionHandler?.decompress(data: data, isFinal: isFinal)
    }
    
    public func didForm(event: FrameCollector.Event) {
        switch event {
        case .text(let string):
            broadcast(event: .text(string))
        case .binary(let data):
            broadcast(event: .binary(data))
        case .pong(let data):
            broadcast(event: .pong(data))
        case .ping(let data):
            broadcast(event: .ping(data))
        case .closed(let reason, let code):
            broadcast(event: .disconnected(reason, code))
        case .error(let error):
            handleError(error)
        }
    }
    
    private func broadcast(event: WebSocketEvent) {
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.delegate?.didReceive(event: event, client: s)
            s.onEvent?(event)
        }
    }
    
    //This call can be coming from a lot of different queues/threads.
    //be aware of that when modifying shared variables
    private func handleError(_ error: Error?) {
        mutex.wait()
        canSend = false
        didUpgrade = false
        mutex.signal()
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.delegate?.didReceive(event: .error(error), client: s)
            s.onEvent?(.error(error))
        }
    }
}
