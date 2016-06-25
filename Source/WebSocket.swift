//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//  Copyright (c) 2014-2015 Dalton Cherry.
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
    func websocketDidReceiveData(socket: WebSocket, data: NSData)
}

public protocol WebSocketPongDelegate: class {
    func websocketDidReceivePong(socket: WebSocket)
}

public class WebSocket : NSObject, NSStreamDelegate {
    
    enum OpCode : UInt8 {
        case ContinueFrame = 0x0
        case TextFrame = 0x1
        case BinaryFrame = 0x2
        //3-7 are reserved.
        case ConnectionClose = 0x8
        case Ping = 0x9
        case Pong = 0xA
        //B-F reserved.
    }
    
    public enum CloseCode : UInt16 {
        case Normal                 = 1000
        case GoingAway              = 1001
        case ProtocolError          = 1002
        case ProtocolUnhandledType  = 1003
        // 1004 reserved.
        case NoStatusReceived       = 1005
        //1006 reserved.
        case Encoding               = 1007
        case PolicyViolated         = 1008
        case MessageTooBig          = 1009
    }

    public static let ErrorDomain = "WebSocket"

    enum InternalErrorCode : UInt16 {
        // 0-999 WebSocket status codes not used
        case OutputStreamWriteError  = 1
    }

    //Where the callback is executed. It defaults to the main UI thread queue.
    public var queue            = dispatch_get_main_queue()

    var optionalProtocols       : [String]?
    //Constant Values.
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
    
    class WSResponse {
        var isFin = false
        var code: OpCode = .ContinueFrame
        var bytesLeft = 0
        var frameCount = 0
        var buffer: NSMutableData?
    }
    
    public weak var delegate: WebSocketDelegate?
    public weak var pongDelegate: WebSocketPongDelegate?
    public var onConnect: ((Void) -> Void)?
    public var onDisconnect: ((NSError?) -> Void)?
    public var onText: ((String) -> Void)?
    public var onData: ((NSData) -> Void)?
    public var onPong: ((Void) -> Void)?
    public var headers = [String: String]()
    public var voipEnabled = false
    public var selfSignedSSL = false
    public var security: SSLSecurity?
    public var enabledSSLCipherSuites: [SSLCipherSuite]?
    public var origin: String?
    public var timeout = 5
    public var isConnected :Bool {
        return connected
    }
    public var currentURL: NSURL {return url}
    private var url: NSURL
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    private var connected = false
    private var isCreated = false
    private var writeQueue = NSOperationQueue()
    private var readStack = [WSResponse]()
    private var inputQueue = [NSData]()
    private var fragBuffer: NSData?
    private var certValidated = false
    private var didDisconnect = false
    private var readyToWrite = false
    private let mutex = NSLock()
    private let notificationCenter = NSNotificationCenter.defaultCenter()
    private var canDispatch: Bool {
        mutex.lock()
        let canWork = readyToWrite
        mutex.unlock()
        return canWork
    }
    //the shared processing queue used for all websocket
    private static let sharedWorkQueue = dispatch_queue_create("com.vluxe.starscream.websocket", DISPATCH_QUEUE_SERIAL)
    
    //used for setting protocols.
    public init(url: NSURL, protocols: [String]? = nil) {
        self.url = url
        self.origin = url.absoluteString
        writeQueue.maxConcurrentOperationCount = 1
        optionalProtocols = protocols
    }
    
    ///Connect to the websocket server on a background thread
    public func connect() {
        guard !isCreated else { return }
        didDisconnect = false
        isCreated = true
        createHTTPRequest()
        isCreated = false
    }

    /**
     Disconnect from the server. I send a Close control frame to the server, then expect the server to respond with a Close control frame and close the socket from its end. I notify my delegate once the socket has been closed.
     
     If you supply a non-nil `forceTimeout`, I wait at most that long (in seconds) for the server to close the socket. After the timeout expires, I close the socket and notify my delegate.
     
     If you supply a zero (or negative) `forceTimeout`, I immediately close the socket (without sending a Close control frame) and notify my delegate.
     
     - Parameter forceTimeout: Maximum time to wait for the server to close the socket.
    */
    public func disconnect(forceTimeout forceTimeout: NSTimeInterval? = nil) {
        switch forceTimeout {
            case .Some(let seconds) where seconds > 0:
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(seconds * Double(NSEC_PER_SEC))), queue) { [weak self] in
                    self?.disconnectStream(nil)
                    }
                fallthrough
            case .None:
                writeError(CloseCode.Normal.rawValue)

            default:
                self.disconnectStream(nil)
                break
        }
    }
    
    /**
     Write a string to the websocket. This sends it as a text frame.
     
     If you supply a non-nil completion block, I will perform it when the write completes.

     - parameter str:        The string to write.
     - parameter completion: The (optional) completion handler.
     */
    public func writeString(str: String, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(str.dataUsingEncoding(NSUTF8StringEncoding)!, code: .TextFrame, writeCompletion: completion)
    }

    /**
     Write binary data to the websocket. This sends it as a binary frame.
     
     If you supply a non-nil completion block, I will perform it when the write completes.

     - parameter data:       The data to write.
     - parameter completion: The (optional) completion handler.
     */
    public func writeData(data: NSData, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(data, code: .BinaryFrame, writeCompletion: completion)
    }
    
    //write a   ping   to the websocket. This sends it as a  control frame.
    //yodel a   sound  to the planet.    This sends it as an astroid. http://youtu.be/Eu5ZJELRiJ8?t=42s
    public func writePing(data: NSData, completion: (() -> ())? = nil) {
        guard isConnected else { return }
        dequeueWrite(data, code: .Ping, writeCompletion: completion)
    }

    //private method that starts the connection
    private func createHTTPRequest() {
        
        let urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET",
            url, kCFHTTPVersion1_1).takeRetainedValue()
        
        var port = url.port
        if port == nil {
            if ["wss", "https"].contains(url.scheme) {
                port = 443
            } else {
                port = 80
            }
        }
        addHeader(urlRequest, key: headerWSUpgradeName, val: headerWSUpgradeValue)
        addHeader(urlRequest, key: headerWSConnectionName, val: headerWSConnectionValue)
        if let protocols = optionalProtocols {
            addHeader(urlRequest, key: headerWSProtocolName, val: protocols.joinWithSeparator(","))
        }
        addHeader(urlRequest, key: headerWSVersionName, val: headerWSVersionValue)
        addHeader(urlRequest, key: headerWSKeyName, val: generateWebSocketKey())
        if let origin = origin {
            addHeader(urlRequest, key: headerOriginName, val: origin)
        }
        addHeader(urlRequest, key: headerWSHostName, val: "\(url.host!):\(port!)")
        for (key,value) in headers {
            addHeader(urlRequest, key: key, val: value)
        }
        if let cfHTTPMessage = CFHTTPMessageCopySerializedMessage(urlRequest) {
            let serializedRequest = cfHTTPMessage.takeRetainedValue()
            initStreamsWithData(serializedRequest, Int(port!))
        }
    }
    
    //Add a header to the CFHTTPMessage by using the NSString bridges to CFString
    private func addHeader(urlRequest: CFHTTPMessage, key: NSString, val: NSString) {
        CFHTTPMessageSetHeaderFieldValue(urlRequest, key, val)
    }
    
    //generate a websocket key as needed in rfc
    private func generateWebSocketKey() -> String {
        var key = ""
        let seed = 16
        for _ in 0..<seed {
            let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
            key += "\(Character(uni))"
        }
        let data = key.dataUsingEncoding(NSUTF8StringEncoding)
        let baseKey = data?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        return baseKey!
    }
    
    //Start the stream connection and write the data to the output stream
    private func initStreamsWithData(data: NSData, _ port: Int) {
        //higher level API we will cut over to at some point
        //NSStream.getStreamsToHostWithName(url.host, port: url.port.integerValue, inputStream: &inputStream, outputStream: &outputStream)
        
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        let h: NSString = url.host!
        CFStreamCreatePairWithSocketToHost(nil, h, UInt32(port), &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        guard let inStream = inputStream, let outStream = outputStream else { return }
        inStream.delegate = self
        outStream.delegate = self
        if ["wss", "https"].contains(url.scheme) {
            inStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outStream.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        } else {
            certValidated = true //not a https session, so no need to check SSL pinning
        }
        if voipEnabled {
            inStream.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
            outStream.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
        }
        if selfSignedSSL {
            let settings: [NSObject: NSObject] = [kCFStreamSSLValidatesCertificateChain: NSNumber(bool:false), kCFStreamSSLPeerName: kCFNull]
            inStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as String)
            outStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as String)
        }
        if let cipherSuites = self.enabledSSLCipherSuites {
            if let sslContextIn = CFReadStreamCopyProperty(inputStream, kCFStreamPropertySSLContext) as! SSLContextRef?,
                   sslContextOut = CFWriteStreamCopyProperty(outputStream, kCFStreamPropertySSLContext) as! SSLContextRef? {
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
        
        let bytes = UnsafePointer<UInt8>(data.bytes)
        var out = timeout * 1000000 //wait 5 seconds before giving up
        writeQueue.addOperationWithBlock { [weak self] in
            while !outStream.hasSpaceAvailable {
                usleep(100) //wait until the socket is ready
                out -= 100
                if out < 0 {
                    self?.cleanupStream()
                    self?.doDisconnect(self?.errorWithDetail("write wait timed out", code: 2))
                    return
                } else if outStream.streamError != nil {
                    return //disconnectStream will be called.
                }
            }
            outStream.write(bytes, maxLength: data.length)
        }
    }
    //delegate for the stream methods. Processes incoming bytes
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        
        if let sec = security where !certValidated && [.HasBytesAvailable, .HasSpaceAvailable].contains(eventCode) {
            let possibleTrust: AnyObject? = aStream.propertyForKey(kCFStreamPropertySSLPeerTrust as String)
            if let trust: AnyObject = possibleTrust {
                let domain: AnyObject? = aStream.propertyForKey(kCFStreamSSLPeerName as String)
                if sec.isValid(trust as! SecTrustRef, domain: domain as! String?) {
                    certValidated = true
                } else {
                    let error = errorWithDetail("Invalid SSL certificate", code: 1)
                    disconnectStream(error)
                    return
                }
            }
        }
        if eventCode == .HasBytesAvailable {
            if aStream == inputStream {
                processInputStream()
            }
        } else if eventCode == .ErrorOccurred {
            disconnectStream(aStream.streamError)
        } else if eventCode == .EndEncountered {
            disconnectStream(nil)
        }
    }
    //disconnect the stream object
    private func disconnectStream(error: NSError?) {
        if error == nil {
            writeQueue.waitUntilAllOperationsAreFinished()
        } else {
            writeQueue.cancelAllOperations()
        }
        cleanupStream()
        doDisconnect(error)
    }
    
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
    
    ///handles the incoming bytes and sending them to the proper processing method
    private func processInputStream() {
        let buf = NSMutableData(capacity: BUFFER_MAX)
        let buffer = UnsafeMutablePointer<UInt8>(buf!.bytes)
        let length = inputStream!.read(buffer, maxLength: BUFFER_MAX)
        
        guard length > 0 else { return }
        var process = false
        if inputQueue.count == 0 {
            process = true
        }
        inputQueue.append(NSData(bytes: buffer, length: length))
        if process {
            dequeueInput()
        }
    }
    ///dequeue the incoming input so it is processed in order
    private func dequeueInput() {
        while !inputQueue.isEmpty {
            let data = inputQueue[0]
            var work = data
            if let fragBuffer = fragBuffer {
                let combine = NSMutableData(data: fragBuffer)
                combine.appendData(data)
                work = combine
                self.fragBuffer = nil
            }
            let buffer = UnsafePointer<UInt8>(work.bytes)
            let length = work.length
            if !connected {
                processTCPHandshake(buffer, bufferLen: length)
            } else {
                processRawMessagesInBuffer(buffer, bufferLen: length)
            }
            inputQueue = inputQueue.filter{$0 != data}
        }
    }
    
    //handle checking the inital connection status
    private func processTCPHandshake(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        let code = processHTTP(buffer, bufferLen: bufferLen)
        switch code {
        case 0:
            connected = true
            guard canDispatch else {return}
            dispatch_async(queue) { [weak self] in
                guard let s = self else { return }
                s.onConnect?()
                s.delegate?.websocketDidConnect(s)
                s.notificationCenter.postNotificationName(WebsocketDidConnectNotification, object: self)
            }
        case -1:
            fragBuffer = NSData(bytes: buffer, length: bufferLen)
            break //do nothing, we are going to collect more data
        default:
            doDisconnect(errorWithDetail("Invalid HTTP upgrade", code: UInt16(code)))
        }
    }
    ///Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
    private func processHTTP(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
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
        return -1 //was unable to find the full TCP header
    }
    
    ///validates the HTTP is a 101 as per the RFC spec
    private func validateResponse(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false).takeRetainedValue()
        CFHTTPMessageAppendBytes(response, buffer, bufferLen)
        let code = CFHTTPMessageGetResponseStatusCode(response)
        if code != 101 {
            return code
        }
        if let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response) {
            let headers = cfHeaders.takeRetainedValue() as NSDictionary
            if let acceptKey = headers[headerWSAcceptName] as? NSString {
                if acceptKey.length > 0 {
                    return 0
                }
            }
        }
        return -1
    }
    
    ///read a 16 bit big endian value from a buffer
    private static func readUint16(buffer: UnsafePointer<UInt8>, offset: Int) -> UInt16 {
        return (UInt16(buffer[offset + 0]) << 8) | UInt16(buffer[offset + 1])
    }
    
    ///read a 64 bit big endian value from a buffer
    private static func readUint64(buffer: UnsafePointer<UInt8>, offset: Int) -> UInt64 {
        var value = UInt64(0)
        for i in 0...7 {
            value = (value << 8) | UInt64(buffer[offset + i])
        }
        return value
    }
    
    ///write a 16 bit big endian value to a buffer
    private static func writeUint16(buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt16) {
        buffer[offset + 0] = UInt8(value >> 8)
        buffer[offset + 1] = UInt8(value & 0xff)
    }
    
    ///write a 64 bit big endian value to a buffer
    private static func writeUint64(buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt64) {
        for i in 0...7 {
            buffer[offset + i] = UInt8((value >> (8*UInt64(7 - i))) & 0xff)
        }
    }

    /// Process one message at the start of `buffer`. Return another buffer (sharing storage) that contains the leftover contents of `buffer` that I didn't process.
    @warn_unused_result
    private func processOneRawMessage(inBuffer buffer: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        let response = readStack.last
        let baseAddress = buffer.baseAddress
        let bufferLen = buffer.count
        if response != nil && bufferLen < 2  {
            fragBuffer = NSData(buffer: buffer)
            return emptyBuffer
        }
        if let response = response where response.bytesLeft > 0 {
            var len = response.bytesLeft
            var extra = bufferLen - response.bytesLeft
            if response.bytesLeft > bufferLen {
                len = bufferLen
                extra = 0
            }
            response.bytesLeft -= len
            response.buffer?.appendData(NSData(bytes: baseAddress, length: len))
            processResponse(response)
            return buffer.fromOffset(bufferLen - extra)
        } else {
            let isFin = (FinMask & baseAddress[0])
            let receivedOpcode = OpCode(rawValue: (OpCodeMask & baseAddress[0]))
            let isMasked = (MaskMask & baseAddress[1])
            let payloadLen = (PayloadLenMask & baseAddress[1])
            var offset = 2
            if (isMasked > 0 || (RSVMask & baseAddress[0]) > 0) && receivedOpcode != .Pong {
                let errCode = CloseCode.ProtocolError.rawValue
                doDisconnect(errorWithDetail("masked and rsv data is not currently supported", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            let isControlFrame = (receivedOpcode == .ConnectionClose || receivedOpcode == .Ping)
            if !isControlFrame && (receivedOpcode != .BinaryFrame && receivedOpcode != .ContinueFrame &&
                receivedOpcode != .TextFrame && receivedOpcode != .Pong) {
                    let errCode = CloseCode.ProtocolError.rawValue
                    doDisconnect(errorWithDetail("unknown opcode: \(receivedOpcode)", code: errCode))
                    writeError(errCode)
                    return emptyBuffer
            }
            if isControlFrame && isFin == 0 {
                let errCode = CloseCode.ProtocolError.rawValue
                doDisconnect(errorWithDetail("control frames can't be fragmented", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            if receivedOpcode == .ConnectionClose {
                var code = CloseCode.Normal.rawValue
                if payloadLen == 1 {
                    code = CloseCode.ProtocolError.rawValue
                } else if payloadLen > 1 {
                    code = WebSocket.readUint16(baseAddress, offset: offset)
                    if code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000) {
                        code = CloseCode.ProtocolError.rawValue
                    }
                    offset += 2
                }
                var closeReason = "connection closed by server"
                if payloadLen > 2 {
                    let len = Int(payloadLen - 2)
                    if len > 0 {
                        let bytes = baseAddress + offset
                        if let customCloseReason = String(data: NSData(bytes: bytes, length: len), encoding: NSUTF8StringEncoding) {
                            closeReason = customCloseReason
                        } else {
                            code = CloseCode.ProtocolError.rawValue
                        }
                    }
                }
                doDisconnect(errorWithDetail(closeReason, code: code))
                writeError(code)
                return emptyBuffer
            }
            if isControlFrame && payloadLen > 125 {
                writeError(CloseCode.ProtocolError.rawValue)
                return emptyBuffer
            }
            var dataLength = UInt64(payloadLen)
            if dataLength == 127 {
                dataLength = WebSocket.readUint64(baseAddress, offset: offset)
                offset += sizeof(UInt64)
            } else if dataLength == 126 {
                dataLength = UInt64(WebSocket.readUint16(baseAddress, offset: offset))
                offset += sizeof(UInt16)
            }
            if bufferLen < offset || UInt64(bufferLen - offset) < dataLength {
                fragBuffer = NSData(bytes: baseAddress, length: bufferLen)
                return emptyBuffer
            }
            var len = dataLength
            if dataLength > UInt64(bufferLen) {
                len = UInt64(bufferLen-offset)
            }
            let data: NSData
            if len < 0 {
                len = 0
                data = NSData()
            } else {
                data = NSData(bytes: baseAddress+offset, length: Int(len))
            }
            if receivedOpcode == .Pong {
                if canDispatch {
                    dispatch_async(queue) { [weak self] in
                        guard let s = self else { return }
                        s.onPong?()
                        s.pongDelegate?.websocketDidReceivePong(s)
                    }
                }
                return buffer.fromOffset(offset + Int(len))
            }
            var response = readStack.last
            if isControlFrame {
                response = nil //don't append pings
            }
            if isFin == 0 && receivedOpcode == .ContinueFrame && response == nil {
                let errCode = CloseCode.ProtocolError.rawValue
                doDisconnect(errorWithDetail("continue frame before a binary or text frame", code: errCode))
                writeError(errCode)
                return emptyBuffer
            }
            var isNew = false
            if response == nil {
                if receivedOpcode == .ContinueFrame  {
                    let errCode = CloseCode.ProtocolError.rawValue
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
                if receivedOpcode == .ContinueFrame  {
                    response!.bytesLeft = Int(dataLength)
                } else {
                    let errCode = CloseCode.ProtocolError.rawValue
                    doDisconnect(errorWithDetail("second and beyond of fragment message must be a continue frame",
                        code: errCode))
                    writeError(errCode)
                    return emptyBuffer
                }
                response!.buffer!.appendData(data)
            }
            if let response = response {
                response.bytesLeft -= Int(len)
                response.frameCount += 1
                response.isFin = isFin > 0 ? true : false
                if isNew {
                    readStack.append(response)
                }
                processResponse(response)
            }
            
            let step = Int(offset+numericCast(len))
            return buffer.fromOffset(step)
        }
    }

    /// Process all messages in the buffer if possible.
    private func processRawMessagesInBuffer(pointer: UnsafePointer<UInt8>, bufferLen: Int) {
        var buffer = UnsafeBufferPointer(start: pointer, count: bufferLen)
        repeat {
            buffer = processOneRawMessage(inBuffer: buffer)
        } while buffer.count >= 2
        if buffer.count > 0 {
            fragBuffer = NSData(buffer: buffer)
        }
    }

    ///process the finished response of a buffer
    private func processResponse(response: WSResponse) -> Bool {
        if response.isFin && response.bytesLeft <= 0 {
            if response.code == .Ping {
                let data = response.buffer! //local copy so it is perverse for writing
                dequeueWrite(data, code: OpCode.Pong)
            } else if response.code == .TextFrame {
                let str: NSString? = NSString(data: response.buffer!, encoding: NSUTF8StringEncoding)
                if str == nil {
                    writeError(CloseCode.Encoding.rawValue)
                    return false
                }
                if canDispatch {
                    dispatch_async(queue) { [weak self] in
                        guard let s = self else { return }
                        s.onText?(str! as String)
                        s.delegate?.websocketDidReceiveMessage(s, text: str! as String)
                    }
                }
            } else if response.code == .BinaryFrame {
                if canDispatch {
                    let data = response.buffer! //local copy so it is perverse for writing
                    dispatch_async(queue) { [weak self] in
                        guard let s = self else { return }
                        s.onData?(data)
                        s.delegate?.websocketDidReceiveData(s, data: data)
                    }
                }
            }
            readStack.removeLast()
            return true
        }
        return false
    }
    
    ///Create an error
    private func errorWithDetail(detail: String, code: UInt16) -> NSError {
        var details = [String: String]()
        details[NSLocalizedDescriptionKey] =  detail
        return NSError(domain: WebSocket.ErrorDomain, code: Int(code), userInfo: details)
    }
    
    ///write a an error to the socket
    private func writeError(code: UInt16) {
        let buf = NSMutableData(capacity: sizeof(UInt16))
        let buffer = UnsafeMutablePointer<UInt8>(buf!.bytes)
        WebSocket.writeUint16(buffer, offset: 0, value: code)
        dequeueWrite(NSData(bytes: buffer, length: sizeof(UInt16)), code: .ConnectionClose)
    }
    ///used to write things to the stream
    private func dequeueWrite(data: NSData, code: OpCode, writeCompletion: (() -> ())? = nil) {
        writeQueue.addOperationWithBlock { [weak self] in
            //stream isn't ready, let's wait
            guard let s = self else { return }
            var offset = 2
            let bytes = UnsafeMutablePointer<UInt8>(data.bytes)
            let dataLength = data.length
            let frame = NSMutableData(capacity: dataLength + s.MaxFrameSize)
            let buffer = UnsafeMutablePointer<UInt8>(frame!.mutableBytes)
            buffer[0] = s.FinMask | code.rawValue
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(UInt16.max) {
                buffer[1] = 126
                WebSocket.writeUint16(buffer, offset: offset, value: UInt16(dataLength))
                offset += sizeof(UInt16)
            } else {
                buffer[1] = 127
                WebSocket.writeUint64(buffer, offset: offset, value: UInt64(dataLength))
                offset += sizeof(UInt64)
            }
            buffer[1] |= s.MaskMask
            let maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
            SecRandomCopyBytes(kSecRandomDefault, Int(sizeof(UInt32)), maskKey)
            offset += sizeof(UInt32)
            
            for i in 0..<dataLength {
                buffer[offset] = bytes[i] ^ maskKey[i % sizeof(UInt32)]
                offset += 1
            }
            var total = 0
            while true {
                guard let outStream = s.outputStream else { break }
                let writeBuffer = UnsafePointer<UInt8>(frame!.bytes+total)
                let len = outStream.write(writeBuffer, maxLength: offset-total)
                if len < 0 {
                    var error: NSError?
                    if let streamError = outStream.streamError {
                        error = streamError
                    } else {
                        let errCode = InternalErrorCode.OutputStreamWriteError.rawValue
                        error = s.errorWithDetail("output stream error during write", code: errCode)
                    }
                    s.doDisconnect(error)
                    break
                } else {
                    total += len
                }
                if total >= offset {
                    if let queue = self?.queue, callback = writeCompletion {
                        dispatch_async(queue) {
                            callback()
                        }
                    }

                    break
                }
            }
            
        }
    }
    
    ///used to preform the disconnect delegate
    private func doDisconnect(error: NSError?) {
        guard !didDisconnect else { return }
        didDisconnect = true
        connected = false
        guard canDispatch else {return}
        dispatch_async(queue) { [weak self] in
            guard let s = self else { return }
            s.onDisconnect?(error)
            s.delegate?.websocketDidDisconnect(s, error: error)
            let userInfo = error.map({ [WebsocketDisconnectionErrorKeyName: $0] })
            s.notificationCenter.postNotificationName(WebsocketDidDisconnectNotification, object: self, userInfo: userInfo)
        }
    }
    
    deinit {
        mutex.lock()
        readyToWrite = false
        mutex.unlock()
        cleanupStream()
    }
    
}

private extension NSData {

    convenience init(buffer: UnsafeBufferPointer<UInt8>) {
        self.init(bytes: buffer.baseAddress, length: buffer.count)
    }

}

private extension UnsafeBufferPointer {

    func fromOffset(offset: Int) -> UnsafeBufferPointer<Element> {
        return UnsafeBufferPointer<Element>(start: baseAddress.advancedBy(offset), count: count - offset)
    }

}

private let emptyBuffer = UnsafeBufferPointer<UInt8>(start: nil, count: 0)

