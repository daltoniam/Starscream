//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
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

public let WebsocketDidConnectNotification = "WebsocketDidConnectNotification"
public let WebsocketDidDisconnectNotification = "WebsocketDidDisconnectNotification"
public let WebsocketDisconnectionErrorKeyName = "WebsocketDisconnectionErrorKeyName"

//Standard WebSocket close codes
public enum CloseCode : UInt16 {
    case normal                 = 1000
    case goingAway              = 1001
    case protocolError          = 1002
    case protocolUnhandledType  = 1003
    // 1004 reserved.
    case noStatusReceived       = 1005
    //1006 reserved.
    case encoding               = 1007
    case policyViolated         = 1008
    case messageTooBig          = 1009
}

public enum ErrorType: Error {
    case outputStreamWriteError //output stream error during write
    case compressionError
    case invalidSSLError //Invalid SSL certificate
    case writeTimeoutError //The socket timed out waiting to be ready to write
    case protocolError //There was an error parsing the WebSocket frames
    case upgradeError //There was an error during the HTTP upgrade
    case closeError //There was an error during the close (socket probably has been dereferenced)
    case expectedClose //This was a proper close code from the websocket
}

public struct WSError: Error {
    public let type: ErrorType
    public let message: String
    public let code: UInt16
}

//WebSocketClient is setup to be dependency injection for testing
public protocol WebSocketClient: class {
    var delegate: WebSocketDelegate? {get set}
    var isConnected: Bool {get}
    
    func connect()
    func disconnect(forceTimeout: TimeInterval?, closeCode: UInt16)
    func write(string: String, completion: (() -> ())?)
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
        disconnect(forceTimeout: nil, closeCode: CloseCode.normal.rawValue)
    }
}

public protocol WSStreamDelegate: class {
    func newBytesInStream()
    func streamDidError(error: Error?)
}

/// This protocol is to allow custom implemention of the underlining stream.
/// This way custom socket libraries can be used.
public protocol WSStream {
    var delegate: WSStreamDelegate? {get set}
    func connect(url: URL, port: Int, timeout: TimeInterval, useSSL: Bool, completion: @escaping ((Error?) -> Void))
    func write(data: Data, completion: @escaping ((Error?) -> Void))
    func read() -> Data?
    func cleanup()
    func isValidSSLCertificate() -> Bool
}

//WebSocket implementation

//standard delegate you should use
public protocol WebSocketDelegate: class {
    func websocketDidConnect(socket: WebSocketClient)
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?)
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String)
    func websocketDidReceiveData(socket: WebSocketClient, data: Data)
}

//got pongs
public protocol WebSocketPongDelegate: class {
    func websocketDidReceivePong(socket: WebSocketClient, data: Data?)
}

// A Delegate for see the HTTP upgrade request and response.
public protocol WebSocketHTTPDelegate: class {
    func websocketHttpUpgrade(socket: WebSocket, request: String)
    func websocketHttpUpgrade(socket: WebSocket, response: String)
}


open class WebSocket: NSObject, StreamDelegate, WebSocketClient, WSStreamDelegate, WSMessageParserDelegate {

    public enum OpCode : UInt8 {
        case continueFrame = 0x0
        case text = 0x1
        case binary = 0x2
        // 3-7 are reserved.
        case connectionClose = 0x8
        case ping = 0x9
        case pong = 0xA
        // B-F reserved.
    }

    public static let ErrorDomain = "WebSocket"

    // Where the callback is executed. It defaults to the main UI thread queue.
    public var callbackQueue = DispatchQueue.main

    // MARK: - Constants

    static let headerWSUpgradeName     = "Upgrade"
    static let headerWSUpgradeValue    = "websocket"
    static let headerWSHostName        = "Host"
    static let headerWSConnectionName  = "Connection"
    static let headerWSConnectionValue = "Upgrade"
    static let headerWSProtocolName    = "Sec-WebSocket-Protocol"
    static let headerWSVersionName     = "Sec-WebSocket-Version"
    static let headerWSVersionValue    = "13"
    static let headerWSExtensionName   = "Sec-WebSocket-Extensions"
    static let headerWSKeyName         = "Sec-WebSocket-Key"
    static let headerOriginName        = "Origin"
    static let headerWSAcceptName      = "Sec-WebSocket-Accept"
    let supportedSSLSchemes     = ["wss", "https"]

    // MARK: - Delegates

    /// Responds to callback about new messages coming in over the WebSocket
    /// and also connection/disconnect messages.
    public weak var delegate: WebSocketDelegate?
    
    /// The optional http delegate to see the HTTP request body and response
    public weak var httpDelegate: WebSocketHTTPDelegate?

    /// Receives a callback for each pong message recived.
    public weak var pongDelegate: WebSocketPongDelegate?
    
    public var onConnect: (() -> Void)?
    public var onDisconnect: ((Error?) -> Void)?
    public var onText: ((String) -> Void)?
    public var onData: ((Data) -> Void)?
    public var onPong: ((Data?) -> Void)?
    
    public var isConnected: Bool {
        mutex.lock()
        let isConnected = connected
        mutex.unlock()
        return isConnected
    }
    
    public var request: URLRequest //this is only public to allow headers, timeout, etc to be modified on reconnect
    public var currentURL: URL { return request.url! }

    public var respondToPingWithPong: Bool = true
    public var enableCompression = true

    // MARK: - Private
    
    private var stream: WSStream
    private var parser = WSMessageParser()
    private var connected = false
    private var isConnecting = false
    private let mutex = NSLock()
    private var writeQueue = DispatchQueue(label: "com.vluxe.starscream.wsframe", attributes: [])
    
    private var certValidated = false
    private var didDisconnect = false
    private var readyToWrite = false
    private var canDispatch: Bool {
        mutex.lock()
        let canWork = readyToWrite
        mutex.unlock()
        return canWork
    }
    
    /**
     main init method.
     - Parameter request: The request to start the WebSocket connection with. This includes custom headers, timeout, etc
     - Parameter protocols: the protocols to send to the websocket server. This is things like "chat" or "superchat".
     - Parameter stream: The WSStream to use for the underlying connection. This also includes your security options.
     */
    public init(request: URLRequest, protocols: [String]? = nil, stream: WSStream = FoundationStream()) {
        self.request = request
        self.stream = stream
        if request.value(forHTTPHeaderField: WebSocket.headerOriginName) == nil, let url = request.url {
            var origin = url.absoluteString
            if let hostUrl = URL (string: "/", relativeTo: url) {
                origin = hostUrl.absoluteString
                origin.remove(at: origin.index(before: origin.endIndex))
            }
            self.request.setValue(origin, forHTTPHeaderField: WebSocket.headerOriginName)
        }
        if let protocols = protocols {
            self.request.setValue(protocols.joined(separator: ","), forHTTPHeaderField: WebSocket.headerWSProtocolName)
        }
        super.init()
        parser.delegate = self
    }
    
    /**
     convenience init to use a URL instead of a URLRequest. Defaults to 5 second timeout.
     - Parameter url: is where to connect the websocket too.
     - Parameter protocols: the protocols to send to the websocket server. This is things like "chat" or "superchat".
     - Parameter stream: The WSStream to use for the underlying connection. This also includes your security options.
     */
    public convenience init(url: URL, protocols: [String]? = nil, stream: WSStream = FoundationStream()) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        self.init(request: request, protocols: protocols, stream: stream)
    }

    /**
     Connect to the WebSocket server on a background thread.
     */
    open func connect() {
        guard !isConnecting else { return }
        didDisconnect = false
        isConnecting = true
        createHTTPRequest()
    }

    /**
     Disconnect from the server. I send a Close control frame to the server, then expect the server to respond with a Close control frame and close the socket from its end. I notify my delegate once the socket has been closed.

     If you supply a non-nil `forceTimeout`, I wait at most that long (in seconds) for the server to close the socket. After the timeout expires, I close the socket and notify my delegate.

     If you supply a zero (or negative) `forceTimeout`, I immediately close the socket (without sending a Close control frame) and notify my delegate.

     - Parameter forceTimeout: Maximum time to wait for the server to close the socket.
     - Parameter closeCode: The code to send on disconnect. The default is the normal close code for cleanly disconnecting a webSocket.
    */
    open func disconnect(forceTimeout: TimeInterval? = nil, closeCode: UInt16 = CloseCode.normal.rawValue) {
        guard isConnected else { return }
        switch forceTimeout {
        case .some(let seconds) where seconds > 0:
            let milliseconds = Int(seconds * 1_000)
            callbackQueue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak self] in
                self?.disconnectStream(nil)
            }
            fallthrough
        case .none:
            writeError(closeCode)
        default:
            disconnectStream(nil)
            break
        }
    }

    /**
     Write a string to the websocket. This sends it as a text frame.

     If you supply a non-nil completion block, I will perform it when the write completes.

     - parameter string:        The string to write.
     - parameter completion: The (optional) completion handler.
     */
    open func write(string: String, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        writeFrame(string.data(using: .utf8)!, code: .text, writeCompletion: completion)
    }

    /**
     Write binary data to the websocket. This sends it as a binary frame.

     If you supply a non-nil completion block, I will perform it when the write completes.

     - parameter data:       The data to write.
     - parameter completion: The (optional) completion handler.
     */
    open func write(data: Data, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        writeFrame(data, code: .binary, writeCompletion: completion)
    }

    /**
     Write a ping to the websocket. This sends it as a control frame.
     Yodel a   sound  to the planet.    This sends it as an astroid. http://youtu.be/Eu5ZJELRiJ8?t=42s
     */
    open func write(ping: Data, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        writeFrame(ping, code: .ping, writeCompletion: completion)
    }

    /**
     Write a pong to the websocket. This sends it as a control frame.
     Respond to a Yodel.
     */
    open func write(pong: Data, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        writeFrame(pong, code: .pong, writeCompletion: completion)
    }
    
    /// MARK: - private methods

    /// Starts the connection.
    private func createHTTPRequest() {
        guard let url = request.url else { return }
        var port = url.port
        if port == nil {
            if supportedSSLSchemes.contains(url.scheme!) {
                port = 443
            } else {
                port = 80
            }
        }
        request.setValue(WebSocket.headerWSUpgradeValue, forHTTPHeaderField: WebSocket.headerWSUpgradeName)
        request.setValue(WebSocket.headerWSConnectionValue, forHTTPHeaderField: WebSocket.headerWSConnectionName)
        request.setValue(WebSocket.headerWSVersionValue, forHTTPHeaderField: WebSocket.headerWSVersionName)
        request.setValue(parser.headerSecurityKey, forHTTPHeaderField: WebSocket.headerWSKeyName)
        
        if enableCompression {
            let val = "permessage-deflate; client_max_window_bits; server_max_window_bits=15"
            request.setValue(val, forHTTPHeaderField: WebSocket.headerWSExtensionName)
        }
        let hostValue = request.allHTTPHeaderFields?[WebSocket.headerWSHostName] ?? "\(url.host!):\(port!)"
        request.setValue(hostValue, forHTTPHeaderField: WebSocket.headerWSHostName)

        var path = url.absoluteString
        let offset = (url.scheme?.count ?? 2) + 3
        path = String(path[path.index(path.startIndex, offsetBy: offset)..<path.endIndex])
        if let range = path.range(of: "/") {
            path = String(path[range.lowerBound..<path.endIndex])
        } else {
            path = "/"
            if let query = url.query {
                path += "?" + query
            }
        }
        
        var httpBody = "\(request.httpMethod ?? "GET") \(path) HTTP/1.1\r\n"
        if let headers = request.allHTTPHeaderFields {
            for (key, val) in headers {
                httpBody += "\(key): \(val)\r\n"
            }
        }
        httpBody += "\r\n"
        
        initStreamsWithData(httpBody.data(using: .utf8)!, Int(port!))
        httpDelegate?.websocketHttpUpgrade(socket: self, request: httpBody)
    }

    /// Start the stream connection and write the data to the output stream.
    private func initStreamsWithData(_ data: Data, _ port: Int) {

        guard let url = request.url else {
            disconnectStream(nil, runDelegate: true)
            return
            
        }
        // Disconnect and clean up any existing streams before setting up a new one
        disconnectStream(nil, runDelegate: false)

        let useSSL = supportedSSLSchemes.contains(url.scheme!)
        
        certValidated = !useSSL
        let timeout = request.timeoutInterval * 1_000_000
        stream.delegate = self
        stream.connect(url: url, port: port, timeout: timeout, useSSL: useSSL, completion: { [weak self] (error) in
            guard let s = self else { return }
            if error != nil {
                s.disconnectStream(error)
                return
            }
            s.writeQueue.async {
                // Do SSL pinning
                if !s.certValidated {
                    s.certValidated = s.stream.isValidSSLCertificate()
                    if !s.certValidated {
                        s.disconnectStream(WSError(type: .invalidSSLError, message: "Invalid SSL certificate", code: 0))
                        return
                    }
                }
                s.stream.write(data: data, completion: { (error) in
                    if let error = error {
                        s.disconnectStream(error)
                    }
                })
            }
        })

        self.mutex.lock()
        self.readyToWrite = true
        self.mutex.unlock()
    }

    /// MARK: - WSStreamDelegate
    
    public func newBytesInStream() {
        guard let data = stream.read() else { return }
        parser.append(data: data)
    }
    
    public func streamDidError(error: Error?) {
        disconnectStream(error)
    }
    
    ///MARK: - WSMessageParserDelegate
    
    func didReceive(message: WSMessage) {
        switch message.code {
        case .ping:
            handlePing(message)
        case .text:
            handleText(message)
        case .binary:
            handleBinary(message)
        case .pong:
            handlePong(message)
        case .connectionClose:
            disconnectStream(nil) // should never fall into this (handled in streamDidError)
        case .continueFrame:
            break //should never fall into this
        }
    }
    
    func didEncounter(error: WSError) {
        writeError(error.code)
    }
    
    func didParseHTTP(response: String) {
        mutex.lock()
        connected = true
        isConnecting = false
        didDisconnect = false
        mutex.unlock()
        guard canDispatch else { return }
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onConnect?()
            s.delegate?.websocketDidConnect(socket: s)
            s.httpDelegate?.websocketHttpUpgrade(socket: s, response: response)
            NotificationCenter.default.post(name: NSNotification.Name(WebsocketDidConnectNotification), object: self)
        }
    }
    
    //MARK: - message handlers

    func handlePing(_ message: WSMessage) {
        if respondToPingWithPong {
            writeFrame(message.data, code: .pong)
        }
    }
    
    func handleText(_ message: WSMessage) {
        guard canDispatch, let str = String(data: message.data, encoding: .utf8) else {
            writeError(CloseCode.encoding.rawValue)
            return
        }
        
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onText?(str)
            s.delegate?.websocketDidReceiveMessage(socket: s, text: str)
        }
    }
    
    func handleBinary(_ message: WSMessage) {
        guard canDispatch else { return }
        
        let data = message.data
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onData?(data)
            s.delegate?.websocketDidReceiveData(socket: s, data: data as Data)
        }
    }
    
    func handlePong(_ message: WSMessage) {
        guard canDispatch else { return }
        
        let pongData: Data? = message.data.count > 0 ? message.data : nil
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onPong?(pongData)
            s.pongDelegate?.websocketDidReceivePong(socket: s, data: pongData)
        }
    }

    //// Disconnect the stream object and notifies the delegate.
    private func disconnectStream(_ error: Error?, runDelegate: Bool = true) {
        mutex.lock()
        stream.cleanup()
        parser.reset()
        connected = false
        mutex.unlock()
        if runDelegate {
            doDisconnect(error)
        }
    }
    
    /// Used to preform the disconnect delegate
    private func doDisconnect(_ error: Error?) {
        guard !didDisconnect else { return }
        didDisconnect = true
        isConnecting = false
        guard canDispatch else { return }
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onDisconnect?(error)
            s.delegate?.websocketDidDisconnect(socket: s, error: error)
            let userInfo = error.map{ [WebsocketDisconnectionErrorKeyName: $0] }
            NotificationCenter.default.post(name: NSNotification.Name(WebsocketDidDisconnectNotification), object: self, userInfo: userInfo)
        }
    }

    /// Write an error to the socket
    private func writeError(_ code: UInt16) {
        let buf = NSMutableData(capacity: MemoryLayout<UInt16>.size)
        let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
        WSMessageParser.writeUint16(buffer, offset: 0, value: code)
        writeFrame(Data(bytes: buffer, count: MemoryLayout<UInt16>.size), code: .connectionClose)
    }

    /// Used to write things to the stream
    private func writeFrame(_ data: Data, code: OpCode, writeCompletion: (() -> ())? = nil) {
        writeQueue.async { [weak self] in
            guard let s = self, s.connected else { return }
            let frame = s.parser.createSendFrame(data: data, code: code)
            s.stream.write(data: frame, completion: {[weak self] (error) in
                self?.callbackQueue.async {
                    writeCompletion?()
                }
            })
        }

    }
    // MARK: - Deinit

    deinit {
        mutex.lock()
        readyToWrite = false
        stream.cleanup()
        mutex.unlock()
    }

}

#if swift(>=4)
#else
fileprivate extension String {
    var count: Int {
        return self.characters.count
    }
}
#endif
