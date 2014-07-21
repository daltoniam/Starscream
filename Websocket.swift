//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation
import CoreFoundation

protocol WebsocketDelegate {
    func websocketDidConnect()
    func websocketDidDisconnect(error: NSError?)
    func websocketDidWriteError(error: NSError?)
    func websocketDidReceiveMessage(text: String)
    func websocketDidReceiveData(data: NSData)
}

class Websocket : NSObject, NSStreamDelegate {
    
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
    //Constant Values.
    let headerWSUpgradeName     = "Upgrade"
    let headerWSUpgradeValue    = "websocket"
    let headerWSHostName        = "Host"
    let headerWSConnectionName  = "Connection"
    let headerWSConnectionValue = "Upgrade"
    let headerWSProtocolName    = "Sec-WebSocket-Protocol"
    let headerWSProtocolValue   = "chat, superchat"
    let headerWSVersionName     = "Sec-Websocket-Version"
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
    
    var delegate: WebsocketDelegate?
    var _url: NSURL
    var _inputStream: NSInputStream?
    var _outputStream: NSOutputStream?
    var _isRunLoop = false
    var _isConnected = false
    var _writeQueue: NSOperationQueue?
    var _readStack = Array<WSResponse>()
    var _inputQueue = Array<NSData>()
    var _fragBuffer: NSData?
    
    //init the websocket with a url
    init(url: NSURL) {
        _url = url
    }
    ///Connect to the websocket server on a background thread
    func connect() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), {
            self.createHTTPRequest()
            })
    }
    
    ///disconnect from the websocket server
    func disconnect() {
        writeError(CloseCode.Normal.toRaw())
    }
    
    ///write a string to the websocket. This sends it as a text frame.
    func writeString(str: String) {
        dequeueWrite(str.dataUsingEncoding(NSUTF8StringEncoding)!, code: .TextFrame)
    }
    
    ///write binary data to the websocket. This sends it as a binary frame.
    func writeData(data: NSData) {
        dequeueWrite(data, code: .BinaryFrame)
    }
    
    //private methods below!
    
    //private method that starts the connection
    func createHTTPRequest() {
        
        let str: NSString = _url.absoluteString
        let url = CFURLCreateWithString(kCFAllocatorDefault, str, nil)
        let urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET",
            url, kCFHTTPVersion1_1)
        
        self.addHeader(urlRequest, key: headerWSUpgradeName, val: headerWSUpgradeValue)
        self.addHeader(urlRequest, key: headerWSConnectionName, val: headerWSConnectionValue)
        self.addHeader(urlRequest, key: headerWSProtocolName, val: headerWSProtocolValue)
        self.addHeader(urlRequest, key: headerWSVersionName, val: headerWSVersionValue)
        self.addHeader(urlRequest, key: headerWSKeyName, val: self.generateWebSocketKey())
        self.addHeader(urlRequest, key: headerOriginName, val: _url.absoluteString)
        self.addHeader(urlRequest, key: headerWSHostName, val: "\(_url.host):\(_url.port)")
        
        let serializedRequest: NSData = CFHTTPMessageCopySerializedMessage(urlRequest.takeUnretainedValue()).takeUnretainedValue()
        self.initStreamsWithData(serializedRequest)
    }
    //Add a header to the CFHTTPMessage by using the NSString bridges to CFString
    func addHeader(urlRequest: Unmanaged<CFHTTPMessage>,key: String, val: String) {
        let nsKey: NSString = key
        let nsVal: NSString = val
        CFHTTPMessageSetHeaderFieldValue(urlRequest.takeUnretainedValue(),
            nsKey,
            nsVal)
    }
    //generate a websocket key as needed in rfc
    func generateWebSocketKey() -> String {
        var key = ""
        let seed = 16
        for (var i = 0; i < seed; i++) {
            let c: unichar =  (97 + UInt16(arc4random_uniform(25)))
            key += "\(c)"
        }
        return key
    }
    //Start the stream connection and write the data to the output stream
    func initStreamsWithData(data: NSData) {
        NSStream.getStreamsToHostWithName(_url.host, port: _url.port.integerValue, inputStream: &_inputStream, outputStream: &_outputStream)
        _inputStream!.delegate = self
        _outputStream!.delegate = self
        _inputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        _outputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        _inputStream!.open()
        _outputStream!.open()
        let bytes = UnsafePointer<UInt8>(data.bytes)
        _outputStream!.write(bytes, maxLength: data.length)
        _isRunLoop = true
        while(_isRunLoop) {
            NSRunLoop.currentRunLoop().runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture() as NSDate)
        }
    }
    //delegate for the stream methods. Processes incoming bytes
    func stream(aStream: NSStream!, handleEvent eventCode: NSStreamEvent) {
        
        if eventCode == .HasBytesAvailable {
            if(aStream == _inputStream) {
                processInputStream()
            }
        } else if eventCode == .ErrorOccurred {
            disconnectStream(aStream!.streamError)
        } else if eventCode == .EndEncountered {
            disconnectStream(nil)
        }
    }
    //work around for a swift bug. BugID: 17712659
    func workaroundMethod() {
        //does nothing, but fixes bug in swift
    }
    //disconnect the stream object
    func disconnectStream(error: NSError?) {
        _writeQueue!.waitUntilAllOperationsAreFinished()
        _inputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        _outputStream!.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        _inputStream!.close()
        _outputStream!.close()
        _inputStream = nil
        _outputStream = nil
        _isRunLoop = false
        _isConnected = false
        dispatch_async(dispatch_get_main_queue(),{
            self.workaroundMethod()
            self.delegate?.websocketDidDisconnect(error)
            })
    }
    
    ///handles the incoming bytes and sending them to the proper processing method
    func processInputStream() {
        let buffer = UnsafePointer<UInt8>(BUFFER_MAX)
        let length = _inputStream!.read(buffer, maxLength: BUFFER_MAX)
        if length > 0 {
            if !_isConnected {
                _isConnected = processHTTP(buffer, bufferLen: length)
                if !_isConnected {
                    dispatch_async(dispatch_get_main_queue(),{
                        self.workaroundMethod()
                        self.delegate?.websocketDidDisconnect(self.errorWithDetail("Invalid HTTP upgrade", code: 1))
                        })
                }
            } else {
                var process = false
                if _inputQueue.count == 0 {
                    process = true
                }
                _inputQueue.append(NSData(bytes: buffer, length: length))
                if process {
                    dequeueInput()
                }
            }
        }
    }
    ///dequeue the incoming input so it is processed in order
    func dequeueInput() {
        if _inputQueue.count > 0 {
            let data = _inputQueue[0]
            var work = data
            if _fragBuffer {
                var combine = NSMutableData(data: _fragBuffer!)
                combine.appendData(data)
                work = combine
                _fragBuffer = nil
            }
            let buffer = UnsafePointer<UInt8>(work.bytes)
            processRawMessage(buffer, bufferLen: work.length)
            _inputQueue = _inputQueue.filter{$0 != data}
            dequeueInput()
        }
    }
    ///Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
    func processHTTP(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
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
                    self.workaroundMethod()
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
    func validateResponse(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
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
    func processRawMessage(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        if _readStack.count > 0 {
            if bufferLen < 2 {
                _fragBuffer = NSData(bytes: buffer, length: bufferLen)
                return
            }
            var response = _readStack[_readStack.count-1]
            if response.bytesLeft > 0 {
                var len = response.bytesLeft
                var extra = bufferLen - response.bytesLeft
                if response.bytesLeft > bufferLen {
                    len = bufferLen
                    extra = 0
                }
                response.bytesLeft -= len
                response.buffer?.appendData(NSData(bytes: buffer, length: len))
                processResponse(response)
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
                if((isMasked > 0 || (RSVMask & buffer[0]) > 0) && receivedOpcode != OpCode.Pong.toRaw()) {
                    
                }
            }
        }
    }
    
    ///process the extra of a buffer
    func processExtra(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        if bufferLen < 2 {
            _fragBuffer = NSData(bytes: buffer, length: bufferLen)
        } else {
            processRawMessage(buffer, bufferLen: bufferLen)
        }
    }
    
    ///process the finished response of a buffer
    func processResponse(response: WSResponse) -> Bool {
        if response.isFin && response.bytesLeft <= 0 {
            if response.code == .Ping {
                let data = response.buffer! //local copy so it is perverse for writing
                dequeueWrite(data, code: OpCode.Pong)
            } else if response.code == .TextFrame {
                var str: NSString? = NSString(data: response.buffer!, encoding: NSUTF8StringEncoding)
                if !str {
                    writeError(CloseCode.Encoding.toRaw())
                    return false
                }
                dispatch_async(dispatch_get_main_queue(),{
                    self.workaroundMethod()
                    self.delegate?.websocketDidReceiveMessage(str!)
                    })
            } else if response.code == .BinaryFrame {
                let data = response.buffer! //local copy so it is perverse for writing
                dispatch_async(dispatch_get_main_queue(),{
                    self.workaroundMethod()
                    self.delegate?.websocketDidReceiveData(data)
                    })
            }
            _readStack.removeLast()
            return true
        }
        return false
    }
    
    ///Create an error
    func errorWithDetail(detail: String, code: Int) -> NSError {
        var details = Dictionary<String,String>()
        details[NSLocalizedDescriptionKey] =  detail
        return NSError(domain: "Websocket", code: code, userInfo: details)
    }
    
    ///write a an error to the socket
    func writeError(code: UInt16) {
        var buffer = UnsafePointer<UInt16>(sizeof(UInt16))
        buffer[0] = code.byteSwapped
        dequeueWrite(NSData(bytes: buffer, length: sizeof(UInt16)), code: .ConnectionClose)
    }
    ///used to write things to the stream in a
    func dequeueWrite(data: NSData, code: OpCode) {
        if !_writeQueue {
            _writeQueue = NSOperationQueue()
            _writeQueue!.maxConcurrentOperationCount = 1
        }
        _writeQueue!.addOperationWithBlock {
            var offset = 2
            let bytes = UnsafePointer<UInt8>(data.bytes)
            let dataLength = data.length
            let frame = NSMutableData(capacity: dataLength + self.MaxFrameSize)
            let buffer = UnsafePointer<UInt8>(frame.mutableBytes)
            buffer[0] = self.FinMask | code.toRaw()
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(Int16.max) {
                buffer[1] = 126
                var sizeBuffer = UnsafePointer<UInt16>((buffer+offset))
                sizeBuffer[0] = UInt16(dataLength).byteSwapped
                offset += sizeof(UInt16)
            } else {
                buffer[1] = 127
                var sizeBuffer = UnsafePointer<UInt64>((buffer+offset))
                sizeBuffer[0] = UInt64(dataLength).byteSwapped
                offset += sizeof(UInt64)
            }
            buffer[1] |= self.MaskMask
            var maskKey = UnsafePointer<UInt8>(buffer + offset)
            SecRandomCopyBytes(kSecRandomDefault, UInt(sizeof(UInt32)), maskKey)
            offset += sizeof(UInt32)
            
            for (var i = 0; i < dataLength; i++) {
                buffer[offset] = bytes[i] ^ maskKey[i % sizeof(UInt32)]
                offset += 1
            }
            var total = 0
            while true {
                if !self._outputStream {
                    break
                }
                let writeBuffer = UnsafePointer<UInt8>(frame.bytes+total)
                var len = self._outputStream!.write(writeBuffer, maxLength: offset-total)
                if len < 0 {
                    self.delegate?.websocketDidDisconnect(self._outputStream!.streamError)
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