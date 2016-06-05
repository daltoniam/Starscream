//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  ProxyConnect.swift
//
//  Created by Dong Liu on 6/3/16
//  Copyright (c) 2016 Dong Liu
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

public class ProxyConnect : NSObject, NSStreamDelegate {
    
    private var url: NSURL
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    
    private var connectDoneHandler: ((error: NSError?, readStream: NSInputStream?, writeStream: NSOutputStream?) -> (Void))?
    
    private var httpProxyHost: NSString?
    private var httpProxyPort = 80
    
    private var receivedHTTPHeaders: CFHTTPMessage?
    
    private var socksProxyHost: NSString?
    private var socksProxyPort: Int?
    private var socksProxyUsername: NSString?
    private var socksProxyPassword: NSString?
    
    private var secure: Bool = false
    
    private var inputQueue = [NSData]()
    private var writeQueue = NSOperationQueue()
    
    private static let sharedWorkQueue = dispatch_queue_create("com.vluxe.starscream.websocket.proxy", DISPATCH_QUEUE_SERIAL)
    
    private let timeout = 5
    private let BUFFER_MAX              = 4096
    
    public init(url: NSURL) {
        self.url = url;
        if ["wss", "https"].contains(url.scheme) {
            self.secure = true
        }
    }
    
    public func openNetworkStream(completionHandler: (error: NSError?, readStream: NSInputStream?, writeStream: NSOutputStream?) -> Void) {
        connectDoneHandler = completionHandler
        configureProxy()
    }
    
    private func didConnect() {
        ProxyFastLog("_didConnect, return streams");
        if secure {
            if httpProxyHost != nil {
                // Must set the real peer name before turning on SSL
                ProxyFastLog("proxy set peer name to real host \(url.host)")
                outputStream?.setProperty(url.host,forKey:"_kCFStreamPropertySocketPeerName")
            }
        }
        
        receivedHTTPHeaders = nil
        
        if let stream = inputStream {
            CFReadStreamSetDispatchQueue(stream, nil)
        }
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        if connectDoneHandler != nil {
            connectDoneHandler!(error: nil, readStream: inputStream, writeStream: outputStream)
        }
        
    }
    
    private func connectionFailed(error: NSError?) {
        ProxyFastLog("_failWithError, return error");
        var err = error
        if err == nil  {
            err  = NSError(domain: "Proxy", code : Int(500),
                           userInfo: [NSLocalizedDescriptionKey:"Proxy Error"])
        }
        
        receivedHTTPHeaders = nil
        
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
        if connectDoneHandler != nil {
            connectDoneHandler!(error: err, readStream: nil, writeStream: nil)
        }
    }
    
    // get proxy setting from device setting
    private func configureProxy () {
        ProxyFastLog("configureProxy");
        var hURL: NSURL? = url;
        if let host = url.host {
            if secure {
                hURL = NSURL(string: "https://"+host)
            } else {
                hURL = NSURL(string: "http://"+host)
            }
        }
        if hURL == nil {
            hURL = url
        }
        if let proxySettings: NSDictionary = CFNetworkCopySystemProxySettings()?.takeRetainedValue() {
            let proxies: NSArray = CFNetworkCopyProxiesForURL(hURL!, proxySettings).takeRetainedValue()
            if proxies.count == 0 {
                ProxyFastLog("configureProxy no proxy")
                initializeStreams()
                return
            }
            
            let settings = proxies[0] as! NSDictionary
            
            if let proxyType: NSString = settings[(kCFProxyTypeKey as NSString)] as? NSString {
                if proxyType == kCFProxyTypeAutoConfigurationURL  {
                    if let pacURL: NSURL = settings[(kCFProxyAutoConfigurationURLKey as NSString)] as? NSURL {
                        fetchPAC(pacURL)
                        return
                    }
                }
                if proxyType == kCFProxyTypeAutoConfigurationJavaScript {
                    if let script: NSString = settings[(kCFProxyAutoConfigurationJavaScriptKey as NSString)] as? NSString {
                        runPACScript(script);
                        return;
                    }
                }
                readProxySetting(proxyType, settings: settings)
            }
            
        }
        initializeStreams()
    }
    
    private func readProxySetting(proxyType: NSString, settings: NSDictionary ){
        if proxyType == kCFProxyTypeHTTP || proxyType == kCFProxyTypeHTTPS {
            httpProxyHost = settings[(kCFProxyHostNameKey as NSString)] as? NSString
            if let portValue: NSNumber = settings[(kCFProxyPortNumberKey as NSString)] as? NSNumber {
                httpProxyPort = portValue.integerValue
            }
        }
        if proxyType == kCFProxyTypeSOCKS {
            socksProxyHost = settings[(kCFProxyHostNameKey as NSString)] as? NSString
            if let portValue: NSNumber = settings[(kCFProxyPortNumberKey as NSString)] as? NSNumber {
                socksProxyPort = portValue.integerValue
            }
            socksProxyUsername = settings[(kCFProxyUsernameKey as NSString)] as? NSString
            socksProxyPassword = settings[(kCFProxyPasswordKey as NSString)] as? NSString
        }
        if let proxyHost = httpProxyHost {
            ProxyFastLog("configureProxy using http proxy \(proxyHost):\(httpProxyPort)")
        } else if let proxyHost = socksProxyHost {
            ProxyFastLog("configureProxy using socks proxy \(proxyHost)")
        } else {
            ProxyFastLog("configureProxy no proxies")
        }
    }
    
    
    private func fetchPAC(PACurl: NSURL) {
        ProxyFastLog("SRWebSocket fetchPAC \(PACurl)")
        
        if PACurl.fileURL {
            do {
                let script = try NSString(contentsOfURL: PACurl, usedEncoding: nil)
                runPACScript(script)
            } catch {
                initializeStreams()
            }
            return;
        }
        
        let scheme = PACurl.scheme.lowercaseString
        if  scheme != "http" && scheme != "https" {
            // Don't know how to read data from this URL, we'll have to give up
            // We'll simply assume no proxies, and start the request as normal
            initializeStreams()
            return
        }
        
        let request = NSURLRequest(URL:PACurl)
        let session = NSURLSession.sharedSession()
        let task = session.dataTaskWithRequest(request) {
            [weak self](data: NSData? , response: NSURLResponse?, error: NSError? )  in
            if error == nil && data != nil {
                if let script = NSString(data: data!, encoding: NSUTF8StringEncoding) {
                    self?.runPACScript(script)
                    return
                }
            }
            self?.initializeStreams()
        }
        task.resume()
    }
    
    private func runPACScript(script: NSString) {
        ProxyFastLog("runPACScript")
        
        // From: http://developer.apple.com/samplecode/CFProxySupportTool/listing1.html
        // Work around <rdar://problem/5530166>.  This dummy call to
        // CFNetworkCopyProxiesForURL initialise some state within CFNetwork
        // that is required by CFNetworkCopyProxiesForAutoConfigurationScript.
        let empty = NSDictionary()
        CFNetworkCopyProxiesForURL(url, empty).takeRetainedValue()
        
        // Obtain the list of proxies by running the autoconfiguration script
        
        // CFNetworkCopyProxiesForAutoConfigurationScript doesn't understand ws:// or wss://
        var hURL: NSURL? = url;
        if let host = url.host {
            if secure {
                hURL = NSURL(string: "https://"+host)
            } else {
                hURL = NSURL(string: "http://"+host)
            }
        }
        if hURL == nil {
            hURL = url
        }
        
        var error: Unmanaged<CFError>?
        let proxies: NSArray? = CFNetworkCopyProxiesForAutoConfigurationScript(script, hURL!, &error)?.takeRetainedValue()
        if  error != nil || proxies == nil {
            initializeStreams()
            return
        }
        if proxies!.count > 0 {
            let settings = proxies![0] as! NSDictionary
            if let proxyType: NSString = settings[(kCFProxyTypeKey as NSString)] as? NSString {
                readProxySetting(proxyType, settings: settings)
            }
        }
        initializeStreams()
    }
    
    private func initializeStreams (){
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        var host: NSString
        var port: UInt32

        if httpProxyHost != nil {
            host = httpProxyHost!
            port =  UInt32(httpProxyPort)
        } else {
            host = url.host!
            if url.port != nil {
                port = UInt32(url.port!.integerValue)
            } else {
                if secure {
                    port = 443
                } else {
                    port = 80
                }
            }
        }
        CFStreamCreatePairWithSocketToHost(nil, host, port, &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        guard let inStream = inputStream, let outStream = outputStream else { return }
        if let sProxy: NSString = socksProxyHost  {
            ProxyFastLog("ProxyConnect set sock property stream to \(sProxy):\(socksProxyPort) user \(socksProxyUsername) password \(socksProxyPassword)")
            let settings = NSMutableDictionary(capacity:4)
            settings[NSStreamSOCKSProxyHostKey] = sProxy
            if let sPort = socksProxyPort {
                settings[NSStreamSOCKSProxyPortKey] = sPort
            }
            if let sName = socksProxyUsername {
                settings[NSStreamSOCKSProxyUserKey] = sName
            }
            if let sPass = socksProxyPassword {
                settings[NSStreamSOCKSProxyPasswordKey] = sPass;
            }
            inputStream!.setProperty(settings, forKey:NSStreamSOCKSProxyConfigurationKey)
            outputStream!.setProperty(settings, forKey:NSStreamSOCKSProxyConfigurationKey)
        }
        inStream.delegate = self
        outStream.delegate = self
        
        CFReadStreamSetDispatchQueue(inStream, ProxyConnect.sharedWorkQueue)
        inStream.open()
        outStream.open()
    }
    
    //delegate for the stream methods. Processes incoming bytes
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        if eventCode == .OpenCompleted {
            if aStream == inputStream  {
                if httpProxyHost != nil {
                    proxyDidConnect();
                } else {
                    didConnect()
                }
            }
        } else if eventCode == .HasBytesAvailable {
            if aStream == inputStream {
                processInputStream()
            }
        } else if eventCode == .ErrorOccurred {
            connectionFailed(aStream.streamError)
        } else if eventCode == .EndEncountered {
            connectionFailed(nil)
        }
    }
    
    // proxy server connected
    private func proxyDidConnect() {
        ProxyFastLog("Proxy Connected")
        let h = url.host!
        var port = url.port
        if port == nil {
            if secure {
                port = 443
            } else {
                port = 80
            }
        }
        // Send HTTP CONNECT Request
        let connectRequestStr = "CONNECT \(h):\(port!) HTTP/1.1\r\nHost: \(h)\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\n\r\n"
        
        ProxyFastLog("Proxy sending \(connectRequestStr)")
        if let data =  connectRequestStr.dataUsingEncoding(NSUTF8StringEncoding) {
            let bytes = UnsafePointer<UInt8>(data.bytes)
            var out = timeout * 1000000 //wait 5 seconds before giving up
            writeQueue.addOperationWithBlock { [weak self] in
                guard let s = self else { return }
                guard let outStream = s.outputStream else { return }
                while !outStream.hasSpaceAvailable {
                    usleep(100) //wait until the socket is ready
                    out -= 100
                    if out < 0 {
                        let error = NSError(domain: "Proxy", code: Int(408), userInfo: [NSLocalizedDescriptionKey:"Proxy timeout"])
                        
                        self?.connectionFailed(error)
                        return
                    } else if outStream.streamError != nil {
                        self?.connectionFailed(outStream.streamError)
                        return
                    }
                }
                outStream.write(bytes, maxLength: data.length)
            }
        }
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
            proxyProcessHTTPResponse(data)
            inputQueue.removeAtIndex(0)
        }
    }
    
    //handle checking the proxy  connection status
    private func proxyProcessHTTPResponse(data: NSData) {
        if receivedHTTPHeaders == nil {
            receivedHTTPHeaders = CFHTTPMessageCreateEmpty(nil, false).takeRetainedValue()
        }
        
        CFHTTPMessageAppendBytes(receivedHTTPHeaders!,  UnsafePointer<UInt8>(data.bytes), data.length)
        if CFHTTPMessageIsHeaderComplete(receivedHTTPHeaders!) {
            ProxyFastLog("Finished reading headers");
            proxyHTTPHeadersDidFinish()
        }
    }
    
    private func proxyHTTPHeadersDidFinish() {
        let responseCode = CFHTTPMessageGetResponseStatusCode(receivedHTTPHeaders!)
        
        if responseCode >= 299 {
            ProxyFastLog("Connect to Proxy Request failed with response code \(responseCode)");
            let error = NSError(domain: "Proxy", code: Int(responseCode),
                                 userInfo: [NSLocalizedDescriptionKey:"Received bad response code from proxy server: \(responseCode)"])
            connectionFailed(error)
            return;
        }
        ProxyFastLog("proxy connect return \(responseCode), call socket connect");
        didConnect()
    }
    
    private let proxyEnableLog = false
    private func  ProxyFastLog(msg: String)  {
        if proxyEnableLog {
            NSLog("%@", msg);
        }
    }
}
