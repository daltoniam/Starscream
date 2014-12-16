//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation
import CoreFoundation

public protocol WebSocketDelegate: class {
    func websocketDidConnect()
    func websocketDidDisconnect(error: NSError?)
    func websocketDidWriteError(error: NSError?)
    func websocketDidReceiveMessage(text: String)
    func websocketDidReceiveData(data: NSData)
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
    
    enum CloseCode : UInt16 {
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
    var optionalProtocols       : Array<String>?
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
    let BUFFER_MAX              = 2048
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
    private var url: NSURL
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    private var isRunLoop = false
    private var connected = false
    private var writeQueue: NSOperationQueue?
    private var readStack = Array<WSResponse>()
    private var inputQueue = Array<NSData>()
    private var fragBuffer: NSData?
    public var headers = Dictionary<String,String>()
    public var voipEnabled = false
    public var selfSignedSSL = false
    private var connectedBlock: ((Void) -> Void)? = nil
    private var disconnectedBlock: ((NSError?) -> Void)? = nil
    private var receivedTextBlock: ((String) -> Void)? = nil
    private var receivedDataBlock: ((NSData) -> Void)? = nil
    public var isConnected :Bool {
        return connected
    }
    
    //init the websocket with a url
    public init(url: NSURL) {
        self.url = url
    }
    //used for setting protocols.
    public convenience init(url: NSURL, protocols: Array<String>) {
        self.init(url: url)
        optionalProtocols = protocols
    }
    //closure based instead of the delegate
    public convenience init(url: NSURL, protocols: Array<String>, connect:((Void) -> Void), disconnect:((NSError?) -> Void), text:((String) -> Void), data:(NSData) -> Void) {
        self.init(url: url, protocols: protocols)
        connectedBlock = connect
        disconnectedBlock = disconnect
        receivedTextBlock = text
        receivedDataBlock = data
    }
    //same as above, just shorter
    public convenience init(url: NSURL, connect:((Void) -> Void), disconnect:((NSError?) -> Void), text:((String) -> Void)) {
        self.init(url: url)
        connectedBlock = connect
        disconnectedBlock = disconnect
        receivedTextBlock = text
    }
    //same as above, just shorter
    public convenience init(url: NSURL, connect:((Void) -> Void), disconnect:((NSError?) -> Void), data:((NSData) -> Void)) {
        self.init(url: url)
        connectedBlock = connect
        disconnectedBlock = disconnect
        receivedDataBlock = data
    }

    ///Connect to the websocket server on a background thread
    public func connect() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), {
            self.createHTTPRequest()
        })
    }
    
    ///disconnect from the websocket server
    public func disconnect() {
        writeError(CloseCode.Normal.rawValue)
    }
    
    ///write a string to the websocket. This sends it as a text frame.
    public func writeString(str: String) {
        dequeueWrite(str.dataUsingEncoding(NSUTF8StringEncoding)!, code: .TextFrame)
    }
    
    ///write binary data to the websocket. This sends it as a binary frame.
    public func writeData(data: NSData) {
        dequeueWrite(data, code: .BinaryFrame)
    }
    //private methods below!
    
    //private method that starts the connection
    private func createHTTPRequest() {
        
        let str: NSString = url.absoluteString!
        let urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET",
            url, kCFHTTPVersion1_1)
        
        var port = url.port
        if port == nil {
            if url.scheme == "wss" || url.scheme == "https" {
                port = 443
            } else {
                port = 80
            }
        }
        self.addHeader(urlRequest, key: headerWSUpgradeName, val: headerWSUpgradeValue)
        self.addHeader(urlRequest, key: headerWSConnectionName, val: headerWSConnectionValue)
        if let protocols = optionalProtocols {
            self.addHeader(urlRequest, key: headerWSProtocolName, val: ",".join(protocols))
        }
        self.addHeader(urlRequest, key: headerWSVersionName, val: headerWSVersionValue)
        self.addHeader(urlRequest, key: headerWSKeyName, val: self.generateWebSocketKey())
        self.addHeader(urlRequest, key: headerOriginName, val: url.absoluteString!)
        self.addHeader(urlRequest, key: headerWSHostName, val: "\(url.host!):\(port!)")
        for (key,value) in headers {
            self.addHeader(urlRequest, key: key, val: value)
        }
        
        let serializedRequest: NSData = CFHTTPMessageCopySerializedMessage(urlRequest.takeUnretainedValue()).takeUnretainedValue()
        self.initStreamsWithData(serializedRequest, Int(port!))
    }
    //Add a header to the CFHTTPMessage by using the NSString bridges to CFString
    private func addHeader(urlRequest: Unmanaged<CFHTTPMessage>,key: String, val: String) {
        let nsKey: NSString = key
        let nsVal: NSString = val
        CFHTTPMessageSetHeaderFieldValue(urlRequest.takeUnretainedValue(),
            nsKey,
            nsVal)
    }
    //generate a websocket key as needed in rfc
    private func generateWebSocketKey() -> String {
        var key = ""
        let seed = 16
        for (var i = 0; i < seed; i++) {
            let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
            key += "\(Character(uni))"
        }
        var data = key.dataUsingEncoding(NSUTF8StringEncoding)
        var baseKey = data?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(0))
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
        inputStream = readStream!.takeUnretainedValue()
        outputStream = writeStream!.takeUnretainedValue()
        
        inputStream!.delegate = self
        outputStream!.delegate = self
        if url.scheme == "wss" || url.scheme == "https" {
            inputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        }
        if self.voipEnabled {
            inputStream!.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
            outputStream!.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
        }
        if self.selfSignedSSL {
            let settings: Dictionary<NSObject, NSObject> = [kCFStreamSSLValidatesCertificateChain: NSNumber(bool:false), kCFStreamSSLPeerName: kCFNull]
            inputStream!.setProperty(settings, forKey: kCFStreamPropertySSLSettings)
            outputStream!.setProperty(settings, forKey: kCFStreamPropertySSLSettings)
        }
        isRunLoop = true
        inputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        inputStream!.open()
        outputStream!.open()
        let bytes = UnsafePointer<UInt8>(data.bytes)
        outputStream!.write(bytes, maxLength: data.length)
        while(isRunLoop) {
            NSRunLoop.currentRunLoop().runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture() as NSDate)
        }
    }
    //delegate for the stream methods. Processes incoming bytes
    func stream(aStream: NSStream!, handleEvent eventCode: NSStreamEvent) {
        
        if eventCode == .HasBytesAvailable {
            if(aStream == inputStream) {
                processInputStream()
            }
        } else if eventCode == .ErrorOccurred {
            disconnectStream(aStream!.streamError)
        } else if eventCode == .EndEncountered {
            disconnectStream(nil)
        }
    }
    //disconnect the stream object
    private func disconnectStream(error: NSError?) {
        if writeQueue != nil {
            writeQueue!.waitUntilAllOperationsAreFinished()
        }
        inputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        inputStream!.close()
        outputStream!.close()
        inputStream = nil
        outputStream = nil
        isRunLoop = false
        connected = false
        dispatch_async(dispatch_get_main_queue(),{
            if let disconnectBlock = self.disconnectedBlock {
                disconnectBlock(error)
            }
            self.delegate?.websocketDidDisconnect(error)
        })
    }
    
    ///handles the incoming bytes and sending them to the proper processing method
    private func processInputStream() {
        let buf = NSMutableData(capacity: BUFFER_MAX)
        var buffer = UnsafeMutablePointer<UInt8>(buf!.bytes)
        let length = inputStream!.read(buffer, maxLength: BUFFER_MAX)
        if length > 0 {
            if !connected {
                connected = processHTTP(buffer, bufferLen: length)
                if !connected {
                    dispatch_async(dispatch_get_main_queue(),{
                        //self.workaroundMethod()
                        let error = self.errorWithDetail("Invalid HTTP upgrade", code: 1)
                        if let disconnect = self.disconnectedBlock {
                            disconnect(error)
                        }
                        self.delegate?.websocketDidDisconnect(error)
                    })
                }
            } else {
                var process = false
                if inputQueue.count == 0 {
                    process = true
                }
                inputQueue.append(NSData(bytes: buffer, length: length))
                if process {
                    dequeueInput()
                }
            }
        }
    }
    ///dequeue the incoming input so it is processed in order
    private func dequeueInput() {
        if inputQueue.count > 0 {
            let data = inputQueue[0]
            var work = data
            if (fragBuffer != nil) {
                var combine = NSMutableData(data: fragBuffer!)
                combine.appendData(data)
                work = combine
                fragBuffer = nil
            }
            let buffer = UnsafePointer<UInt8>(work.bytes)
            processRawMessage(buffer, bufferLen: work.length)
            inputQueue = inputQueue.filter{$0 != data}
            dequeueInput()
        }
    }
    ///Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
    private func processHTTP(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
        let CRLFBytes = [UInt8("\r"), UInt8("\n"), UInt8("\r"), UInt8("\n")]
        var k = 0
        var totalSize = 0
        for var i = 0; i < bufferLen; i++ {
            if buffer[i] == CRLFBytes[k] {
                k++
                if k == 3 {
                    totalSize = i + 1
                    break
                }
            } else {
                k = 0
            }
        }
        if totalSize > 0 {
            if validateResponse(buffer, bufferLen: totalSize) {
                dispatch_async(dispatch_get_main_queue(),{
                    //self.workaroundMethod()
                    if let connectBlock = self.connectedBlock {
                        connectBlock()
                    }
                    self.delegate?.websocketDidConnect()
                })
                totalSize += 1 //skip the last \n
                let restSize = bufferLen - totalSize
                if restSize > 0 {
                    processRawMessage((buffer+totalSize),bufferLen: restSize)
                }
                return true
            }
        }
        return false
    }
    
    ///validates the HTTP is a 101 as per the RFC spec
    private func validateResponse(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, 0)
        CFHTTPMessageAppendBytes(response.takeUnretainedValue(), buffer, bufferLen)
        if CFHTTPMessageGetResponseStatusCode(response.takeUnretainedValue()) != 101 {
            return false
        }
        let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response.takeUnretainedValue())
        let headers: NSDictionary = cfHeaders.takeUnretainedValue()
        let acceptKey = headers[headerWSAcceptName] as NSString
        if acceptKey.length > 0 {
            return true
        }
        return false
    }
    
    ///process the websocket data
    private func processRawMessage(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        var response = readStack.last
        if response != nil && bufferLen < 2  {
            fragBuffer = NSData(bytes: buffer, length: bufferLen)
            return
        }
        if response != nil && response!.bytesLeft > 0 {
            let resp = response!
            var len = resp.bytesLeft
            var extra = bufferLen - resp.bytesLeft
            if resp.bytesLeft > bufferLen {
                len = bufferLen
                extra = 0
            }
            resp.bytesLeft -= len
            resp.buffer?.appendData(NSData(bytes: buffer, length: len))
            processResponse(resp)
            var offset = bufferLen - extra
            if extra > 0 {
                processExtra((buffer+offset), bufferLen: extra)
            }
            return
        } else {
            let isFin = (FinMask & buffer[0])
            let receivedOpcode = (OpCodeMask & buffer[0])
            let isMasked = (MaskMask & buffer[1])
            let payloadLen = (PayloadLenMask & buffer[1])
            var offset = 2
            if((isMasked > 0 || (RSVMask & buffer[0]) > 0) && receivedOpcode != OpCode.Pong.rawValue) {
                let errCode = CloseCode.ProtocolError.rawValue
                let error = self.errorWithDetail("masked and rsv data is not currently supported", code: errCode)
                if let disconnect = self.disconnectedBlock {
                    disconnect(error)
                }
                self.delegate?.websocketDidDisconnect(error)
                writeError(errCode)
                    
                return
            }
            let isControlFrame = (receivedOpcode == OpCode.ConnectionClose.rawValue || receivedOpcode == OpCode.Ping.rawValue)
            if !isControlFrame && (receivedOpcode != OpCode.BinaryFrame.rawValue && receivedOpcode != OpCode.ContinueFrame.rawValue &&
                receivedOpcode != OpCode.TextFrame.rawValue && receivedOpcode != OpCode.Pong.rawValue) {
                    let errCode = CloseCode.ProtocolError.rawValue
                    let error = self.errorWithDetail("unknown opcode: \(receivedOpcode)", code: errCode)
                    if let disconnect = self.disconnectedBlock {
                        disconnect(error)
                    }
                    self.delegate?.websocketDidDisconnect(error)
                    writeError(errCode)
                    return
            }
            if isControlFrame && isFin == 0 {
                let errCode = CloseCode.ProtocolError.rawValue
                let error = self.errorWithDetail("control frames can't be fragmented", code: errCode)
                if let disconnect = self.disconnectedBlock {
                    disconnect(error)
                }
                self.delegate?.websocketDidDisconnect(error)
                writeError(errCode)
                return
            }
            if receivedOpcode == OpCode.ConnectionClose.rawValue {
                var code = CloseCode.Normal.rawValue
                if payloadLen == 1 {
                    code = CloseCode.ProtocolError.rawValue
                } else if payloadLen > 1 {
                    var codeBuffer = UnsafePointer<UInt16>((buffer+offset))
                    code = codeBuffer[0].byteSwapped
                    if code < 1000 || (code > 1003 && code < 1007) || (code > 1011 && code < 3000) {
                        code = CloseCode.ProtocolError.rawValue
                    }
                    offset += 2
                }
                if payloadLen > 2 {
                    let len = Int(payloadLen-2)
                    if len > 0 {
                        let bytes = UnsafePointer<UInt8>((buffer+offset))
                        var str: NSString? = NSString(data: NSData(bytes: bytes, length: len), encoding: NSUTF8StringEncoding)
                        if str == nil {
                            code = CloseCode.ProtocolError.rawValue
                        }
                    }
                }
                writeError(code)
                return
            }
            if isControlFrame && payloadLen > 125 {
                writeError(CloseCode.ProtocolError.rawValue)
                return
            }
            var dataLength = UInt64(payloadLen)
            if dataLength == 127 {
                let bytes = UnsafePointer<UInt64>((buffer+offset))
                dataLength = bytes[0].byteSwapped
                offset += sizeof(UInt64)
            } else if dataLength == 126 {
                let bytes = UnsafePointer<UInt16>((buffer+offset))
                dataLength = UInt64(bytes[0].byteSwapped)
                offset += sizeof(UInt16)
            }
            var len = dataLength
            if dataLength > UInt64(bufferLen) {
                len = UInt64(bufferLen-offset)
            }
            var data: NSData!
            if len < 0 {
                len = 0
                data = NSData()
            } else {
                data = NSData(bytes: UnsafePointer<UInt8>((buffer+offset)), length: Int(len))
            }
            if receivedOpcode == OpCode.Pong.rawValue {
                let step = Int(offset+len)
                let extra = bufferLen-step
                if extra > 0 {
                    processRawMessage((buffer+step), bufferLen: extra)
                }
                return
            }
            var response = readStack.last
            if isControlFrame {
                response = nil //don't append pings
            }
            if isFin == 0 && receivedOpcode == OpCode.ContinueFrame.rawValue && response == nil {
                let errCode = CloseCode.ProtocolError.rawValue
                let error = self.errorWithDetail("continue frame before a binary or text frame", code: errCode)
                if let disconnect = self.disconnectedBlock {
                    disconnect(error)
                }
                self.delegate?.websocketDidDisconnect(error)
                writeError(errCode)
                return
            }
            var isNew = false
            if(response == nil) {
                if receivedOpcode == OpCode.ContinueFrame.rawValue  {
                    let errCode = CloseCode.ProtocolError.rawValue
                    let error = self.errorWithDetail("first frame can't be a continue frame",
                        code: errCode)
                    if let disconnect = self.disconnectedBlock {
                        disconnect(error)
                    }
                    self.delegate?.websocketDidDisconnect(error)
                    writeError(errCode)
                    return
                }
                isNew = true
                response = WSResponse()
                response!.code = OpCode(rawValue: receivedOpcode)!
                response!.bytesLeft = Int(dataLength)
                response!.buffer = NSMutableData(data: data)
            } else {
                if receivedOpcode == OpCode.ContinueFrame.rawValue  {
                    response!.bytesLeft = Int(dataLength)
                } else {
                    let errCode = CloseCode.ProtocolError.rawValue
                    let error = self.errorWithDetail("second and beyond of fragment message must be a continue frame",
                        code: errCode)
                    if let disconnect = self.disconnectedBlock {
                        disconnect(error)
                    }
                    self.delegate?.websocketDidDisconnect(error)
                    writeError(errCode)
                    return
                }
                response!.buffer!.appendData(data)
            }
            if response != nil {
                response!.bytesLeft -= Int(len)
                response!.frameCount++
                response!.isFin = isFin > 0 ? true : false
                if(isNew) {
                    readStack.append(response!)
                }
                processResponse(response!)
            }
            
            let step = Int(offset+len)
            let extra = bufferLen-step
            if(extra > 0) {
                processExtra((buffer+step), bufferLen: extra)
            }
        }
        
    }
    
    ///process the extra of a buffer
    private func processExtra(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        if bufferLen < 2 {
            fragBuffer = NSData(bytes: buffer, length: bufferLen)
        } else {
            processRawMessage(buffer, bufferLen: bufferLen)
        }
    }
    
    ///process the finished response of a buffer
    private func processResponse(response: WSResponse) -> Bool {
        if response.isFin && response.bytesLeft <= 0 {
            if response.code == .Ping {
                let data = response.buffer! //local copy so it is perverse for writing
                dequeueWrite(data, code: OpCode.Pong)
            } else if response.code == .TextFrame {
                var str: NSString? = NSString(data: response.buffer!, encoding: NSUTF8StringEncoding)
                if str == nil {
                    writeError(CloseCode.Encoding.rawValue)
                    return false
                }
                dispatch_async(dispatch_get_main_queue(),{
                    if let textBlock = self.receivedTextBlock{
                        textBlock(str!)
                    }
                    self.delegate?.websocketDidReceiveMessage(str!)
                })
            } else if response.code == .BinaryFrame {
                let data = response.buffer! //local copy so it is perverse for writing
                dispatch_async(dispatch_get_main_queue(),{
                    //self.workaroundMethod()
                    if let dataBlock = self.receivedDataBlock{
                        dataBlock(data)
                    }
                    self.delegate?.websocketDidReceiveData(data)
                })
            }
            readStack.removeLast()
            return true
        }
        return false
    }
    
    ///Create an error
    private func errorWithDetail(detail: String, code: UInt16) -> NSError {
        var details = Dictionary<String,String>()
        details[NSLocalizedDescriptionKey] =  detail
        return NSError(domain: "Websocket", code: Int(code), userInfo: details)
    }
    
    ///write a an error to the socket
    private func writeError(code: UInt16) {
        let buf = NSMutableData(capacity: sizeof(UInt16))
        var buffer = UnsafeMutablePointer<UInt16>(buf!.bytes)
        buffer[0] = code.byteSwapped
        dequeueWrite(NSData(bytes: buffer, length: sizeof(UInt16)), code: .ConnectionClose)
    }
    ///used to write things to the stream in a
    private func dequeueWrite(data: NSData, code: OpCode) {
        if writeQueue == nil {
            writeQueue = NSOperationQueue()
            writeQueue!.maxConcurrentOperationCount = 1
        }
        writeQueue!.addOperationWithBlock {
            //stream isn't ready, let's wait
            var tries = 0;
            while self.outputStream == nil || !self.connected {
                if(tries < 5) {
                    sleep(1);
                } else {
                    break;
                }
                tries++;
            }
            if !self.connected {
                return
            }
            var offset = 2
            UINT16_MAX
            let bytes = UnsafeMutablePointer<UInt8>(data.bytes)
            let dataLength = data.length
            let frame = NSMutableData(capacity: dataLength + self.MaxFrameSize)
            let buffer = UnsafeMutablePointer<UInt8>(frame!.mutableBytes)
            buffer[0] = self.FinMask | code.rawValue
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(UInt16.max) {
                buffer[1] = 126
                var sizeBuffer = UnsafeMutablePointer<UInt16>((buffer+offset))
                sizeBuffer[0] = UInt16(dataLength).byteSwapped
                offset += sizeof(UInt16)
            } else {
                buffer[1] = 127
                var sizeBuffer = UnsafeMutablePointer<UInt64>((buffer+offset))
                sizeBuffer[0] = UInt64(dataLength).byteSwapped
                offset += sizeof(UInt64)
            }
            buffer[1] |= self.MaskMask
            var maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
            SecRandomCopyBytes(kSecRandomDefault, UInt(sizeof(UInt32)), maskKey)
            offset += sizeof(UInt32)
            
            for (var i = 0; i < dataLength; i++) {
                buffer[offset] = bytes[i] ^ maskKey[i % sizeof(UInt32)]
                offset += 1
            }
            var total = 0
            while true {
                if self.outputStream == nil {
                    break
                }
                let writeBuffer = UnsafePointer<UInt8>(frame!.bytes+total)
                var len = self.outputStream!.write(writeBuffer, maxLength: offset-total)
                if len < 0 {
                    if let disconnect = self.disconnectedBlock {
                        disconnect(self.outputStream!.streamError!)
                    }
                    self.delegate?.websocketDidDisconnect(self.outputStream!.streamError)
                    break
                } else {
                    total += len
                }
                if total >= offset {
                    break
                }
            }
            
        }
    }
    
}
