//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//
//  Created by Dalton Cherry on 7/16/14.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation

protocol WebsocketDelegate {
    func websocketDidDisconnect(error: NSError?)
}

class Websocket : NSObject, NSStreamDelegate {
    
    //Constant Header Values.
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
    
    //Class Constants
    let BUFFER_MAX = 2048
    
    var _url: NSURL
    var _inputStream: NSInputStream?
    var _outputStream: NSOutputStream?
    var _isRunLoop = false
    var _isConnected = false
    var _writeQueue: NSOperationQueue?
    var delegate: WebsocketDelegate?
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
        
    }
    
    ///write a string to the websocket. This sends it as a text frame.
    func writeString(str: String) {
        
    }
    
    ///write binary data to the websocket. This sends it as a binary frame.
    func writeData(data: NSData) {
        
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
                
            }
        } else if eventCode == .ErrorOccurred {
            disconnectStream(aStream!.streamError)
        } else if eventCode == .EndEncountered {
            disconnectStream(nil)
        }
    }
    func bugMethod() {
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
            self.bugMethod()
            self.delegate?.websocketDidDisconnect(error)
            })
    }
}