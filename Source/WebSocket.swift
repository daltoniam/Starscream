//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//  Copyright (c) 2014-2016 Dalton Cherry.
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
import CoreFoundation
import Security

public let WebsocketDidConnectNotification = "WebsocketDidConnectNotification"
public let WebsocketDidDisconnectNotification = "WebsocketDidDisconnectNotification"
public let WebsocketDisconnectionErrorKeyName = "WebsocketDisconnectionErrorKeyName"

public protocol WebSocketDelegate: class {
    func websocketDidConnect(socket: WebSocket)
    func websocketDidDisconnect(socket: WebSocket, error: NSError?)
    func websocketDidReceiveMessage(socket: WebSocket, text: String)
    func websocketDidReceiveData(socket: WebSocket, data: Data)
}

public protocol WebSocketPongDelegate: class {
    func websocketDidReceivePong(socket: WebSocket, data: Data?)
}

public class WebSocket : NSObject, StreamDelegate {
    
    enum OpCode : UInt8 {
        case continueFrame = 0x0
        case textFrame = 0x1
        case binaryFrame = 0x2
        // 3-7 are reserved.
        case connectionClose = 0x8
        case ping = 0x9
        case pong = 0xA
        // B-F reserved.
    }
    
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

    public static let ErrorDomain = "WebSocket"

    enum InternalErrorCode: UInt16 {
        // 0-999 WebSocket status codes not used
        case outputStreamWriteError = 1
    }

    // Where the callback is executed. It defaults to the main UI thread queue.
    public var callbackQueue = DispatchQueue.main

    var optionalProtocols: [String]?

    // MARK: - Constants

    let headerWSUpgradeName     = "Upgrade"
    let headerWSUpgradeValue    = "websocket"
    let headerWSHostName        = "Host"
    let headerWSConnectionName  = "Connection"
    let headerWSConnectionValue = "Upgrade"
    let headerWSProtocolName    = "Sec-WebSocket-Protocol"
    let headerWSVersionName     = "Sec-WebSocket-Version"
    let headerWSVersionValue    = "13"
    let headerWSKeyName         = "Sec-WebSocket-Key"
    let headerOriginName        = "Origin"
    let headerWSAcceptName      = "Sec-WebSocket-Accept"
    let BUFFER_MAX              = 4096
    let FinMask: UInt8          = 0x80
    let OpCodeMask: UInt8       = 0x0F
    let RSVMask: UInt8          = 0x70
    let MaskMask: UInt8         = 0x80
    let PayloadLenMask: UInt8   = 0x7F
    let MaxFrameSize: Int       = 32
    let httpSwitchProtocolCode  = 101
    let supportedSSLSchemes     = ["wss", "https"]

    class WSResponse {
        var isFin = false
        var code: OpCode = .continueFrame
        var bytesLeft = 0
        var frameCount = 0
        var buffer: NSMutableData?
    }

    // MARK: - Delegates

    /// Responds to callback about new messages coming in over the WebSocket
    /// and also connection/disconnect messages.
    public weak var delegate: WebSocketDelegate?

    /// Receives a callback for each pong message recived.
    public weak var pongDelegate: WebSocketPongDelegate?


    // MARK: - Block based API.

    public var onConnect: ((Void) -> Void)?
    public var onDisconnect: ((NSError?) -> Void)?
    public var onText: ((String) -> Void)?
    public var onData: ((Data) -> Void)?
    public var onPong: ((Data?) -> Void)?

    public var headers = [String: String]()
    public var voipEnabled = false
    public var disableSSLCertValidation = false
    public var security: SSLSecurity?
    public var enabledSSLCipherSuites: [SSLCipherSuite]?
    public var origin: String?
    public var timeout = 5
    public var isConnected: Bool {
        return connected
    }
    
    public var currentURL: URL { return url }

    // MARK: - Private

    private var url: URL
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var connected = false
    private var isConnecting = false
    private var writeQueue = OperationQueue()
    private var readStack = [WSResponse]()
    private var inputQueue = [Data]()
    private var fragBuffer: Data?
    private var certValidated = false
    private var didDisconnect = false
    private var readyToWrite = false
    private let mutex = NSLock()
    private let notificationCenter = NotificationCenter.default
    private var canDispatch: Bool {
        mutex.lock()
        let canWork = readyToWrite
        mutex.unlock()
        return canWork
    }
    /// The shared processing queue used for all WebSocket.
    private static let sharedWorkQueue = DispatchQueue(label: "com.vluxe.starscream.websocket", attributes: [])
    
    /// Used for setting protocols.
    public init(url: URL, protocols: [String]? = nil) {
        self.url = url
        self.origin = url.absoluteString
        writeQueue.maxConcurrentOperationCount = 1
        optionalProtocols = protocols
    }
    
    // Used for specifically setting the QOS for the write queue.
    public convenience init(url: URL, writeQueueQOS: QualityOfService, protocols: [String]? = nil) {
        self.init(url: url, protocols: protocols)
        writeQueue.qualityOfService = writeQueueQOS
    }

    /**
     Connect to the WebSocket server on a background thread.
     */
    public func connect() {
        guard !isConnecting else { return }
        didDisconnect = false
        isConnecting = true
        createHTTPRequest()
        isConnecting = false
    }

    /**
     Disconnect from the server. I send a Close control frame to the server, then expect the server to respond with a Close control frame and close the socket from its end. I notify my delegate once the socket has been closed.

     If you supply a non-nil `forceTimeout`, I wait at most that long (in seconds) for the server to close the socket. After the timeout expires, I close the socket and notify my delegate.

     If you supply a zero (or negative) `forceTimeout`, I immediately close the socket (without sending a Close control frame) and notify my delegate.

     - Parameter forceTimeout: Maximum time to wait for the server to close the socket.
     - Parameter closeCode: The code to send on disconnect. The default is the normal close code for cleanly disconnecting a webSocket.
    */
    public func disconnect(forceTimeout: TimeInterval? = nil, closeCode: UInt16 = CloseCode.normal.rawValue) {
        switch forceTimeout {
        case .some(let seconds) where seconds > 0:
            callbackQueue.asyncAfter(deadline: DispatchTime.now() + Double(Int64(seconds * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) { [weak self] in
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

     - parameter str:        The string to write.
     - parameter completion: The (optional) completion handler.
     */
    public func write(string: String, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(string.data(using: String.Encoding.utf8)!, code: .textFrame, writeCompletion: completion)
    }

    /**
     Write binary data to the websocket. This sends it as a binary frame.

     If you supply a non-nil completion block, I will perform it when the write completes.

     - parameter data:       The data to write.
     - parameter completion: The (optional) completion handler.
     */
    public func write(data: Data, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(data, code: .binaryFrame, writeCompletion: completion)
    }
    
    /**
     Write a ping to the websocket. This sends it as a control frame.
     Yodel a   sound  to the planet.    This sends it as an astroid. http://youtu.be/Eu5ZJELRiJ8?t=42s
     */
    public func write(ping: Data, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(ping, code: .ping, writeCompletion: completion)
    }

    /**
     Private method that starts the connection.
     */
    private func createHTTPRequest() {

        let urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET" as CFString,
                                                    url as CFURL, kCFHTTPVersion1_1).takeRetainedValue()

        var port = url.port
        if port == nil {
            if supportedSSLSchemes.contains(url.scheme!) {
                port = 443
            } else {
                port = 80
            }
        }
        addHeader(urlRequest, key: headerWSUpgradeName, val: headerWSUpgradeValue)
        addHeader(urlRequest, key: headerWSConnectionName, val: headerWSConnectionValue)
        if let protocols = optionalProtocols {
            addHeader(urlRequest, key: headerWSProtocolName, val: protocols.joined(separator: ","))
        }
        addHeader(urlRequest, key: headerWSVersionName, val: headerWSVersionValue)
        addHeader(urlRequest, key: headerWSKeyName, val: generateWebSocketKey())
        if let origin = origin {
            addHeader(urlRequest, key: headerOriginName, val: origin)
        }
        addHeader(urlRequest, key: headerWSHostName, val: "\(url.host!):\(port!)")
        for (key, value) in headers {
            addHeader(urlRequest, key: key, val: value)
        }
        if let cfHTTPMessage = CFHTTPMessageCopySerializedMessage(urlRequest) {
            let serializedRequest = cfHTTPMessage.takeRetainedValue()
            initStreamsWithData(serializedRequest as Data, Int(port!))
        }
    }
    
    /**
     Add a header to the CFHTTPMessage by using the NSString bridges to CFString
     */
    private func addHeader(_ urlRequest: CFHTTPMessage, key: String, val: String) {
        CFHTTPMessageSetHeaderFieldValue(urlRequest, key as CFString, val as CFString)
    }

    /**
     Generate a WebSocket key as needed in RFC.
     */
    private func generateWebSocketKey() -> String {
        var key = ""
        let seed = 16
        for _ in 0..<seed {
            let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
            key += "\(Character(uni!))"
        }
        let data = key.data(using: String.Encoding.utf8)
        let baseKey = data?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        return baseKey!
    }
    
    /**
     Start the stream connection and write the data to the output stream.
     */
    private func initStreamsWithData(_ data: Data, _ port: Int) {
        //higher level API we will cut over to at some point
        //NSStream.getStreamsToHostWithName(url.host, port: url.port.integerValue, inputStream: &inputStream, outputStream: &outputStream)

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        let h = url.host! as NSString
        CFStreamCreatePairWithSocketToHost(nil, h, UInt32(port), &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        guard let inStream = inputStream, let outStream = outputStream else { return }
        inStream.delegate = self
        outStream.delegate = self
        if supportedSSLSchemes.contains(url.scheme!) {
            inStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
            outStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
        } else {
            certValidated = true //not a https session, so no need to check SSL pinning
        }
        if voipEnabled {
            inStream.setProperty(StreamNetworkServiceTypeValue.voIP as AnyObject, forKey: Stream.PropertyKey.networkServiceType)
            outStream.setProperty(StreamNetworkServiceTypeValue.voIP as AnyObject, forKey: Stream.PropertyKey.networkServiceType)
        }
        if disableSSLCertValidation {
            let settings: [NSObject: NSObject] = [kCFStreamSSLValidatesCertificateChain: NSNumber(value: false), kCFStreamSSLPeerName: kCFNull]
            inStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
            outStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        }
        if let cipherSuites = self.enabledSSLCipherSuites {
            if let sslContextIn = CFReadStreamCopyProperty(inputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext?,
                let sslContextOut = CFWriteStreamCopyProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext? {
                let resIn = SSLSetEnabledCiphers(sslContextIn, cipherSuites, cipherSuites.count)
                let resOut = SSLSetEnabledCiphers(sslContextOut, cipherSuites, cipherSuites.count)
                if resIn != errSecSuccess {
                    let error = self.errorWithDetail("Error setting ingoing cypher suites", code: UInt16(resIn))
                    disconnectStream(error)
                    return
                }
                if resOut != errSecSuccess {
                    let error = self.errorWithDetail("Error setting outgoing cypher suites", code: UInt16(resOut))
                    disconnectStream(error)
                    return
                }
            }
        }
        
        CFReadStreamSetDispatchQueue(inStream, WebSocket.sharedWorkQueue)
        CFWriteStreamSetDispatchQueue(outStream, WebSocket.sharedWorkQueue)
        inStream.open()
        outStream.open()

        self.mutex.lock()
        self.readyToWrite = true
        self.mutex.unlock()
        
        let bytes = UnsafeRawPointer((data as NSData).bytes).assumingMemoryBound(to: UInt8.self)
        var out = timeout * 1000000 // wait 5 seconds before giving up
        writeQueue.addOperation { [weak self] in
            while !outStream.hasSpaceAvailable {
                usleep(100) // wait until the socket is ready
                out -= 100
                if out < 0 {
                    self?.cleanupStream()
                    self?.doDisconnect(self?.errorWithDetail("write wait timed out", code: 2))
                    return
                } else if outStream.streamError != nil {
                    return // disconnectStream will be called.
                }
            }
            outStream.write(bytes, maxLength: data.count)
        }
    }
    
    /**
     Delegate for the stream methods. Processes incoming bytes
     */
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if let sec = security, !certValidated && [.hasBytesAvailable, .hasSpaceAvailable].contains(eventCode) {
            let trust = aStream.property(forKey: kCFStreamPropertySSLPeerTrust as Stream.PropertyKey) as AnyObject
            let domain = aStream.property(forKey: kCFStreamSSLPeerName as Stream.PropertyKey) as? String
            if sec.isValid(trust as! SecTrust, domain: domain) {
                certValidated = true
            } else {
                let error = errorWithDetail("Invalid SSL certificate", code: 1)
                disconnectStream(error)
                return
            }
        }
        if eventCode == .hasBytesAvailable {
            if aStream == inputStream {
                processInputStream()
            }
        } else if eventCode == .errorOccurred {
            disconnectStream(aStream.streamError as NSError?)
        } else if eventCode == .endEncountered {
            disconnectStream(nil)
        }
    }
    
    /**
     Disconnect the stream object and notifies the delegate.
     */
    private func disconnectStream(_ error: NSError?) {
        if error == nil {
            writeQueue.waitUntilAllOperationsAreFinished()
        } else {
            writeQueue.cancelAllOperations()
        }
        cleanupStream()
        doDisconnect(error)
    }

    /**
     cleanup the streams.
     */
    private func cleanupStream() {
        outputStream?.delegate = nil
        inputStream?.delegate = nil
        if let stream = inputStream {
            CFReadStreamSetDispatchQueue(stream, nil)
            stream.close()
        }
        if let stream = outputStream {
            CFWriteStreamSetDispatchQueue(stream, nil)
            stream.close()
        }
        outputStream = nil
        inputStream = nil
    }

    /**
     Handles the incoming bytes and sending them to the proper processing method.
     */
    private func processInputStream() {
        let buf = NSMutableData(capacity: BUFFER_MAX)
        let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
        let length = inputStream!.read(buffer, maxLength: BUFFER_MAX)

        guard length > 0 else { return }
        var process = false
        if inputQueue.count == 0 {
            process = true
        }
        inputQueue.append(Data(bytes: buffer, count: length))
        if process {
            dequeueInput()
        }
    }

    /**
     Dequeue the incoming input so it is processed in order.
     */
    private func dequeueInput() {
        while !inputQueue.isEmpty {
            let data = inputQueue[0]
            var work = data
            if let fragBuffer = fragBuffer {
                var combine = NSData(data: fragBuffer) as Data
                combine.append(data)
                work = combine
                self.fragBuffer = nil
            }
            let buffer = UnsafeRawPointer((work as NSData).bytes).assumingMemoryBound(to: UInt8.self)
            let length = work.count
            if !connected {
                processTCPHandshake(buffer, bufferLen: length)
            } else {
                processRawMessagesInBuffer(buffer, bufferLen: length)
            }
            inputQueue = inputQueue.filter{ $0 != data }
        }
    }
    
    /**
     Handle checking the inital connection status
     */
    private func processTCPHandshake(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        let code = processHTTP(buffer, bufferLen: bufferLen)
        switch code {
        case 0:
            connected = true
            guard canDispatch else {return}
            callbackQueue.async { [weak self] in
                guard let s = self else { return }
                s.onConnect?()
                s.delegate?.websocketDidConnect(socket: s)
                s.notificationCenter.post(name: NSNotification.Name(WebsocketDidConnectNotification), object: self)
            }
        case -1:
            fragBuffer = Data(bytes: buffer, count: bufferLen)
        break // do nothing, we are going to collect more data
        default:
            doDisconnect(errorWithDetail("Invalid HTTP upgrade", code: UInt16(code)))
        }
    }
    
    /**
     Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
     */
    private func processHTTP(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
        let CRLFBytes = [UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\n")]
        var k = 0
        var totalSize = 0
        for i in 0..<bufferLen {
            if buffer[i] == CRLFBytes[k] {
                k += 1
                if k == 3 {
                    totalSize = i + 1
                    break
                }
            } else {
                k = 0
            }
        }
        if totalSize > 0 {
            let code = validateResponse(buffer, bufferLen: totalSize)
            if code != 0 {
                return code
            }
            totalSize += 1 //skip the last \n
            let restSize = bufferLen - totalSize
            if restSize > 0 {
                processRawMessagesInBuffer(buffer + totalSize, bufferLen: restSize)
            }
            return 0 //success
        }
        return -1 // Was unable to find the full TCP header.
    }
    
    /**
     Validates the HTTP is a 101 as per the RFC spec.
     */
    private func validateResponse(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false).takeRetainedValue()
        CFHTTPMessageAppendBytes(response, buffer, bufferLen)
        let code = CFHTTPMessageGetResponseStatusCode(response)
        if code != httpSwitchProtocolCode {
            return code
        }
        if let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response) {
            let headers = cfHeaders.takeRetainedValue() as NSDictionary
            if let acceptKey = headers[headerWSAcceptName as NSString] as? NSString {
                if acceptKey.length > 0 {
                    return 0
                }
            }
        }
        return -1
    }
    
    /**
     Read a 16 bit big endian value from a buffer
     */
    private static func readUint16(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt16 {
        return (UInt16(buffer[offset + 0]) << 8) | UInt16(buffer[offset + 1])
    }
    
    /**
     Read a 64 bit big endian value from a buffer
     */
    private static func readUint64(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt64 {
        var value = UInt64(0)
        for i in 0...7 {
            value = (value << 8) | UInt64(buffer[offset + i])
        }
        return value
    }
    
    /**
     Write a 16-bit big endian value to a buffer.
     */
    private static func writeUint16(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt16) {
        buffer[offset + 0] = UInt8(value >> 8)
        buffer[offset + 1] = UInt8(value & 0xff)
    }
    
    /**
     Write a 64-bit big endian value to a buffer.
     */
    private static func writeUint64(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt64) {
        for i in 0...7 {
            buffer[offset + i] = UInt8((value >> (8*UInt64(7 - i))) & 0xff)
        }
    }

    /**
     Process one message at the start of `buffer`. Return another buffer (sharing storage) that contains the leftover contents of `buffer` that I didn't process.
     */
    private func processOneRawMessage(inBuffer buffer: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        let response = readStack.last
        guard let baseAddress = buffer.baseAddress else {return emptyBuffer}
        let bufferLen = buffer.count
        if response != nil && bufferLen < 2 {
            fragBuffer = Data(buffer: buffer)
            return emptyBuffer
        }
        if let response = response, response.bytesLeft > 0 {
            var len = response.bytesLeft
            var extra = bufferLen - response.bytesLeft
            if response.bytesLeft > bufferLen {
                len = bufferLen
                extra = 0
            }
            response.bytesLeft -= len
            response.buffer?.append(Data(bytes: baseAddress, count: len))
            _ = processResponse(response)
            return buffer.fromOffset(bufferLen - extra)
        } else {
            let isFin = (FinMask & baseAddress[0])
            let receivedOpcode = OpCode(rawValue: (OpCodeMask & baseAddress[0]))
            let isMasked = (MaskMask & baseAddress[1])
            let payloadLen = (PayloadLenMask & baseAddress[1])
            var offset = 2
            if (isMasked > 0 || (RSVMask & baseAddress[0]) > 0) && receivedOpcode != .pong {
                let errCode = CloseCode.protocolError.rawValue
                doDisconnect(errorWithDetail("masked and rsv data is not currently supported", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            let isControlFrame = (receivedOpcode == .connectionClose || receivedOpcode == .ping)
            if !isControlFrame && (receivedOpcode != .binaryFrame && receivedOpcode != .continueFrame &&
                receivedOpcode != .textFrame && receivedOpcode != .pong) {
                    let errCode = CloseCode.protocolError.rawValue
                    doDisconnect(errorWithDetail("unknown opcode: \(receivedOpcode)", code: errCode))
                    writeError(errCode)
                    return emptyBuffer
            }
            if isControlFrame && isFin == 0 {
                let errCode = CloseCode.protocolError.rawValue
                doDisconnect(errorWithDetail("control frames can't be fragmented", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            if receivedOpcode == .connectionClose {
                var code = CloseCode.normal.rawValue
                if payloadLen == 1 {
                    code = CloseCode.protocolError.rawValue
                } else if payloadLen > 1 {
                    code = WebSocket.readUint16(baseAddress, offset: offset)
                    if code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000) {
                        code = CloseCode.protocolError.rawValue
                    }
                    offset += 2
                }
                var closeReason = "connection closed by server"
                if payloadLen > 2 {
                    let len = Int(payloadLen - 2)
                    if len > 0 {
                        let bytes = baseAddress + offset
                        if let customCloseReason = String(data: Data(bytes: bytes, count: len), encoding: .utf8) {
                            closeReason = customCloseReason
                        } else {
                            code = CloseCode.protocolError.rawValue
                        }
                    }
                }
                doDisconnect(errorWithDetail(closeReason, code: code))
                writeError(code)
                return emptyBuffer
            }
            if isControlFrame && payloadLen > 125 {
                writeError(CloseCode.protocolError.rawValue)
                return emptyBuffer
            }
            var dataLength = UInt64(payloadLen)
            if dataLength == 127 {
                dataLength = WebSocket.readUint64(baseAddress, offset: offset)
                offset += MemoryLayout<UInt64>.size
            } else if dataLength == 126 {
                dataLength = UInt64(WebSocket.readUint16(baseAddress, offset: offset))
                offset += MemoryLayout<UInt16>.size
            }
            if bufferLen < offset || UInt64(bufferLen - offset) < dataLength {
                fragBuffer = Data(bytes: baseAddress, count: bufferLen)
                return emptyBuffer
            }
            var len = dataLength
            if dataLength > UInt64(bufferLen) {
                len = UInt64(bufferLen-offset)
            }
            let data: Data
            if len < 0 {
                len = 0
                data = Data()
            } else {
                data = Data(bytes: baseAddress+offset, count: Int(len))
            }
            if receivedOpcode == .pong {
                if canDispatch {
                    callbackQueue.async { [weak self] in
                        guard let s = self else { return }
                        let pongData: Data? = data.count > 0 ? data : nil
                        s.onPong?(pongData)
                        s.pongDelegate?.websocketDidReceivePong(socket: s, data: pongData)
                    }
                }
                return buffer.fromOffset(offset + Int(len))
            }
            var response = readStack.last
            if isControlFrame {
                response = nil // Don't append pings.
            }
            if isFin == 0 && receivedOpcode == .continueFrame && response == nil {
                let errCode = CloseCode.protocolError.rawValue
                doDisconnect(errorWithDetail("continue frame before a binary or text frame", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            var isNew = false
            if response == nil {
                if receivedOpcode == .continueFrame {
                    let errCode = CloseCode.protocolError.rawValue
                    doDisconnect(errorWithDetail("first frame can't be a continue frame",
                        code: errCode))
                    writeError(errCode)
                    return emptyBuffer
                }
                isNew = true
                response = WSResponse()
                response!.code = receivedOpcode!
                response!.bytesLeft = Int(dataLength)
                response!.buffer = NSMutableData(data: data)
            } else {
                if receivedOpcode == .continueFrame {
                    response!.bytesLeft = Int(dataLength)
                } else {
                    let errCode = CloseCode.protocolError.rawValue
                    doDisconnect(errorWithDetail("second and beyond of fragment message must be a continue frame",
                        code: errCode))
                    writeError(errCode)
                    return emptyBuffer
                }
                response!.buffer!.append(data)
            }
            if let response = response {
                response.bytesLeft -= Int(len)
                response.frameCount += 1
                response.isFin = isFin > 0 ? true : false
                if isNew {
                    readStack.append(response)
                }
                _ = processResponse(response)
            }

            let step = Int(offset + numericCast(len))
            return buffer.fromOffset(step)
        }
    }

    /**
     Process all messages in the buffer if possible.     
     */
    private func processRawMessagesInBuffer(_ pointer: UnsafePointer<UInt8>, bufferLen: Int) {
        var buffer = UnsafeBufferPointer(start: pointer, count: bufferLen)
        repeat {
            buffer = processOneRawMessage(inBuffer: buffer)
        } while buffer.count >= 2
        if buffer.count > 0 {
            fragBuffer = Data(buffer: buffer)
        }
    }

    /**
     Process the finished response of a buffer.
     */
    private func processResponse(_ response: WSResponse) -> Bool {
        if response.isFin && response.bytesLeft <= 0 {
            if response.code == .ping {
                let data = response.buffer! // local copy so it is perverse for writing
                dequeueWrite(data as Data, code: .pong)
            } else if response.code == .textFrame {
                let str: NSString? = NSString(data: response.buffer! as Data, encoding: String.Encoding.utf8.rawValue)
                if str == nil {
                    writeError(CloseCode.encoding.rawValue)
                    return false
                }
                if canDispatch {
                    callbackQueue.async { [weak self] in
                        guard let s = self else { return }
                        s.onText?(str! as String)
                        s.delegate?.websocketDidReceiveMessage(socket: s, text: str! as String)
                    }
                }
            } else if response.code == .binaryFrame {
                if canDispatch {
                    let data = response.buffer! // local copy so it is perverse for writing
                    callbackQueue.async { [weak self] in
                        guard let s = self else { return }
                        s.onData?(data as Data)
                        s.delegate?.websocketDidReceiveData(socket: s, data: data as Data)
                    }
                }
            }
            readStack.removeLast()
            return true
        }
        return false
    }
    
    /**
     Create an error
     */
    private func errorWithDetail(_ detail: String, code: UInt16) -> NSError {
        var details = [String: String]()
        details[NSLocalizedDescriptionKey] =  detail
        return NSError(domain: WebSocket.ErrorDomain, code: Int(code), userInfo: details)
    }
    
    /**
     Write an error to the socket
     */
    private func writeError(_ code: UInt16) {
        let buf = NSMutableData(capacity: MemoryLayout<UInt16>.size)
        let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
        WebSocket.writeUint16(buffer, offset: 0, value: code)
        dequeueWrite(Data(bytes: buffer, count: MemoryLayout<UInt16>.size), code: .connectionClose)
    }
    
    /**
     Used to write things to the stream
     */
    private func dequeueWrite(_ data: Data, code: OpCode, writeCompletion: (() -> ())? = nil) {
        writeQueue.addOperation { [weak self] in
            //stream isn't ready, let's wait
            guard let s = self else { return }
            var offset = 2
            let dataLength = data.count
            let frame = NSMutableData(capacity: dataLength + s.MaxFrameSize)
            let buffer = UnsafeMutableRawPointer(frame!.mutableBytes).assumingMemoryBound(to: UInt8.self)
            buffer[0] = s.FinMask | code.rawValue
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(UInt16.max) {
                buffer[1] = 126
                WebSocket.writeUint16(buffer, offset: offset, value: UInt16(dataLength))
                offset += MemoryLayout<UInt16>.size
            } else {
                buffer[1] = 127
                WebSocket.writeUint64(buffer, offset: offset, value: UInt64(dataLength))
                offset += MemoryLayout<UInt64>.size
            }
            buffer[1] |= s.MaskMask
            let maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
            _ = SecRandomCopyBytes(kSecRandomDefault, Int(MemoryLayout<UInt32>.size), maskKey)
            offset += MemoryLayout<UInt32>.size
            
            for i in 0..<dataLength {
                buffer[offset] = data[i] ^ maskKey[i % MemoryLayout<UInt32>.size]
                offset += 1
            }
            var total = 0
            while true {
                guard let outStream = s.outputStream else { break }
                let writeBuffer = UnsafeRawPointer(frame!.bytes+total).assumingMemoryBound(to: UInt8.self)
                let len = outStream.write(writeBuffer, maxLength: offset-total)
                if len < 0 {
                    var error: Error?
                    if let streamError = outStream.streamError {
                        error = streamError
                    } else {
                        let errCode = InternalErrorCode.outputStreamWriteError.rawValue
                        error = s.errorWithDetail("output stream error during write", code: errCode)
                    }
                    s.doDisconnect(error as NSError?)
                    break
                } else {
                    total += len
                }
                if total >= offset {
                    if let queue = self?.callbackQueue, let callback = writeCompletion {
                        queue.async {
                            callback()
                        }
                    }

                    break
                }
            }

        }
    }
    
    /**
     Used to preform the disconnect delegate
     */
    private func doDisconnect(_ error: NSError?) {
        guard !didDisconnect else { return }
        didDisconnect = true
        connected = false
        guard canDispatch else {return}
        callbackQueue.async { [weak self] in
            guard let s = self else { return }
            s.onDisconnect?(error)
            s.delegate?.websocketDidDisconnect(socket: s, error: error)
            let userInfo = error.map{ [WebsocketDisconnectionErrorKeyName: $0] }
            s.notificationCenter.post(name: NSNotification.Name(WebsocketDidDisconnectNotification), object: self, userInfo: userInfo)
        }
    }

    // MARK: - Deinit

    deinit {
        mutex.lock()
        readyToWrite = false
        mutex.unlock()
        cleanupStream()
    }

}

private extension Data {

    init(buffer: UnsafeBufferPointer<UInt8>) {
        self.init(bytes: buffer.baseAddress!, count: buffer.count)
    }

}

private extension UnsafeBufferPointer {

    func fromOffset(_ offset: Int) -> UnsafeBufferPointer<Element> {
        return UnsafeBufferPointer<Element>(start: baseAddress?.advanced(by: offset), count: count - offset)
    }
    
}

private let emptyBuffer = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
