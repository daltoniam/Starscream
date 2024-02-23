//
//  UrlSessionEngine.swift
//  Starscream
//
//  Created by Gary Hughes on 22/9/20.
//  Copyright © 2020. All rights reserved.
//
import Foundation

// This engine implementation provides transparent proxy support for macOS 10.11 onwards which is not possible with the WSEngine implementation.
@available(macOS 10.11, *)
public class UrlSessionEngine : NSObject, Engine, FramerEventClient, FrameCollectorDelegate, HTTPHandlerDelegate
{
    var urlSession: URLSession? = nil
    var streamTask: URLSessionStreamTask? = nil
    
    weak var delegate: EngineDelegate?

    let compressionHandler: CompressionHandler?
    let frameHandler = FrameCollector()
    let headerChecker: HeaderValidator = FoundationSecurity()
    let framer: Framer = WSFramer()
    let httpHandler: HTTPHandler = FoundationHTTPHandler()
    
    var didUpgrade = false
    var secKeyValue = ""
    var request: URLRequest!
  
    public var respondToPingWithPong: Bool = true
    
    // It is useful to ignore errors caused by invalid or self signed certificates etc particularly
    // in development environments.
    public var acceptAnyCredentials: Bool = false
    
    
    public init(compressionHandler: CompressionHandler? = nil)
    {
        self.compressionHandler = compressionHandler
        super.init()
        framer.register(delegate: self)
        httpHandler.register(delegate: self)
        framer.updateCompression(supports: compressionHandler != nil)
        frameHandler.delegate = self
    }
    
    public func register(delegate: EngineDelegate)
    {
        self.delegate = delegate
    }
    
    public func start(request: URLRequest)
    {
        self.request = request
        
        guard let host = request.url?.host, let port = request.url?.port else {
            return
        }
     
        urlSession = URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: self, delegateQueue: OperationQueue.main)
        
        guard let session = urlSession else {
            return
        }
        
        streamTask = session.streamTask(withHostName: host, port: port)
        
        guard let task = streamTask else {
            return
        }
     
        if request.url?.scheme == "https" {
            task.startSecureConnection()
        }
     
        task.resume()
        doRead()
        
        secKeyValue = HTTPWSHeader.generateWebSocketKey()
        let wsReq = HTTPWSHeader.createUpgrade(request: request, supportsCompression: framer.supportsCompression(), secKeyValue: secKeyValue)
        let data = httpHandler.convert(request: wsReq)
        write(data: data, opcode: .binaryFrame) {}
    }
    
    public func stop(closeCode: UInt16 = CloseCode.normal.rawValue)
    {
        streamTask?.cancel()
    }
    
    public func forceStop()
    {
        streamTask?.cancel()
    }
    
    private func doRead()
    {
        guard let task = streamTask else {
            return
        }
        
        task.readData(ofMinLength: 2, maxLength: Int.max, timeout: 0) { [weak self] data, atEOF, error in
        
            guard let welf = self else {
                return
            }
            
            if let error = error {
                welf.stop()
                welf.broadcast(event: .error(error))
                return
            }
    
            if atEOF {
                welf.stop()
                welf.broadcast(event: .disconnected("read failed with eof", 0))
                return
            }
            
            if let data = data {
                if welf.didUpgrade {
                    welf.framer.add(data: data)
                } else {
                    let offset = welf.httpHandler.parse(data: data)
                    if offset > 0 {
                        let extraData = data.subdata(in: offset..<data.endIndex)
                        welf.framer.add(data: extraData)
                    }
                }
            }
       
            welf.doRead()
        }
    }
    
    public func write(data: Data, opcode: FrameOpCode, completion: (() -> ())?)
    {
        var isCompressed = false
        var sendData = data
        if let compressedData = compressionHandler?.compress(data: data) {
            sendData = compressedData
            isCompressed = true
        }
        
        guard let task = streamTask else {
            return
        }
        
        switch opcode {
        case .pong:
            fallthrough
        case .binaryFrame:
            if self.didUpgrade {
                sendData = framer.createWriteFrame(opcode: opcode, payload: data, isCompressed: isCompressed)
            }
            task.write(sendData, timeout: 0) { error in
                if let error = error {
                    self.stop()
                    self.broadcast(event: .disconnected(error.localizedDescription, 0))
                    return
                }
                if let completion = completion {
                    completion()
                }
            }
        case .textFrame:
            let text = String(data: data, encoding: .utf8)!
            write(string: text, completion: completion)
        default:
            break
        }
    }
    
    public func write(string: String, completion: (() -> ())?)
    {
        let data = string.data(using: .utf8)!
        write(data: data, opcode: .textFrame, completion: completion)
    }
    
    private func broadcast(event: WebSocketEvent)
    {
        delegate?.didReceive(event: event)
    }
    
    private func handleError(_ error: Error?) {
        if let wsError = error as? WSError {
            stop(closeCode: wsError.code)
        } else {
            stop()
        }
        
        delegate?.didReceive(event: .error(error))
    }
    
    // MARK: - HTTPHandlerDelegate
    
    public func didReceiveHTTP(event: HTTPEvent) {
        switch event {
        case .success(let headers):
            if let error = headerChecker.validate(headers: headers, key: secKeyValue) {
                handleError(error)
                return
            }
            didUpgrade = true
            compressionHandler?.load(headers: headers)
            if let url = request.url {
                HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).forEach {
                    HTTPCookieStorage.shared.setCookie($0)
                }
            }

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
            if respondToPingWithPong {
                write(data: data ?? Data(), opcode: .pong, completion: nil)
            }
        case .closed(let reason, let code):
            broadcast(event: .disconnected(reason, code))
            stop(closeCode: code)
        case .error(let error):
            handleError(error)
        }
    }
}

@available(macOS 10.11, *)
extension UrlSessionEngine : URLSessionDelegate
{
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        if acceptAnyCredentials {
            completionHandler(.useCredential,  URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
        else {
            completionHandler(.performDefaultHandling, challenge.proposedCredential)
        }
    }
}
