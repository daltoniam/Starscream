//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  WSStream.swift
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

public protocol WSStreamDelegate: class {
	func newBytesInStream()
	func streamDidError(error: Error?)
}

//This protocol is to allow custom implemention of the underlining stream. This way custom socket libraries (e.g. linux) can be used
public protocol WSStream {
	var delegate: WSStreamDelegate? {get set}
	func connect(url: URL, port: Int, timeout: TimeInterval, ssl: SSLSettings, completion: @escaping ((Error?) -> Void))
	func write(data: Data) -> Int
	func read() -> Data?
	func cleanup()
	#if os(Linux) || os(watchOS)
	#else
	func sslTrust() -> (trust: SecTrust?, domain: String?)
	#endif
}

open class FoundationStream : NSObject, WSStream, StreamDelegate  {
	private static let sharedWorkQueue = DispatchQueue(label: "com.vluxe.starscream.websocket", attributes: [])
	private var inputStream: InputStream?
	private var outputStream: OutputStream?
	public weak var delegate: WSStreamDelegate?
	let BUFFER_MAX = 4096
	
	public var enableSOCKSProxy = false
	
	public func connect(url: URL, port: Int, timeout: TimeInterval, ssl: SSLSettings, completion: @escaping ((Error?) -> Void)) {
		var readStream: Unmanaged<CFReadStream>?
		var writeStream: Unmanaged<CFWriteStream>?
		let h = url.host! as NSString
		CFStreamCreatePairWithSocketToHost(nil, h, UInt32(port), &readStream, &writeStream)
		inputStream = readStream!.takeRetainedValue()
		outputStream = writeStream!.takeRetainedValue()
		
		#if os(watchOS) //watchOS us unfortunately is missing the kCFStream properties to make this work
		#else
		if enableSOCKSProxy {
			let proxyDict = CFNetworkCopySystemProxySettings()
			let socksConfig = CFDictionaryCreateMutableCopy(nil, 0, proxyDict!.takeRetainedValue())
			let propertyKey = CFStreamPropertyKey(rawValue: kCFStreamPropertySOCKSProxy)
			CFWriteStreamSetProperty(outputStream, propertyKey, socksConfig)
			CFReadStreamSetProperty(inputStream, propertyKey, socksConfig)
		}
		#endif
		
		guard let inStream = inputStream, let outStream = outputStream else { return }
		inStream.delegate = self
		outStream.delegate = self
		if ssl.useSSL {
			inStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
			outStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL as AnyObject, forKey: Stream.PropertyKey.socketSecurityLevelKey)
			#if os(watchOS) //watchOS us unfortunately is missing the kCFStream properties to make this work
			#else
			var settings = [NSObject: NSObject]()
			if ssl.disableCertValidation {
				settings[kCFStreamSSLValidatesCertificateChain] = NSNumber(value: false)
			}
			if ssl.overrideTrustHostname {
				if let hostname = ssl.desiredTrustHostname {
					settings[kCFStreamSSLPeerName] = hostname as NSString
				} else {
					settings[kCFStreamSSLPeerName] = kCFNull
				}
			}
			if let sslClientCertificate = ssl.sslClientCertificate {
				settings[kCFStreamSSLCertificates] = sslClientCertificate.streamSSLCertificates
			}
			
			inStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
			outStream.setProperty(settings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
			#endif
			
			#if os(Linux)
			#else
			if let cipherSuites = ssl.cipherSuites {
				#if os(watchOS) //watchOS us unfortunately is missing the kCFStream properties to make this work
				#else
				if let sslContextIn = CFReadStreamCopyProperty(inputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext?,
					let sslContextOut = CFWriteStreamCopyProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext? {
					let resIn = SSLSetEnabledCiphers(sslContextIn, cipherSuites, cipherSuites.count)
					let resOut = SSLSetEnabledCiphers(sslContextOut, cipherSuites, cipherSuites.count)
					if resIn != errSecSuccess {
						completion(WSError(type: .invalidSSLError, message: "Error setting ingoing cypher suites", code: Int(resIn)))
					}
					if resOut != errSecSuccess {
						completion(WSError(type: .invalidSSLError, message: "Error setting outgoing cypher suites", code: Int(resOut)))
					}
				}
				#endif
			}
			#endif
		}
		
		CFReadStreamSetDispatchQueue(inStream, FoundationStream.sharedWorkQueue)
		CFWriteStreamSetDispatchQueue(outStream, FoundationStream.sharedWorkQueue)
		inStream.open()
		outStream.open()
		
		var out = timeout// wait X seconds before giving up
		FoundationStream.sharedWorkQueue.async { [weak self] in
			while !outStream.hasSpaceAvailable {
				usleep(100) // wait until the socket is ready
				out -= 100
				if out < 0 {
					completion(WSError(type: .writeTimeoutError, message: "Timed out waiting for the socket to be ready for a write", code: 0))
					return
				} else if let error = outStream.streamError {
					completion(error)
					return // disconnectStream will be called.
				} else if self == nil {
					completion(WSError(type: .closeError, message: "socket object has been dereferenced", code: 0))
					return
				}
			}
			completion(nil) //success!
		}
	}
	
	public func write(data: Data) -> Int {
		guard let outStream = outputStream else {return -1}
		let buffer = UnsafeRawPointer((data as NSData).bytes).assumingMemoryBound(to: UInt8.self)
		return outStream.write(buffer, maxLength: data.count)
	}
	
	public func read() -> Data? {
		guard let stream = inputStream else {return nil}
		let buf = NSMutableData(capacity: BUFFER_MAX)
		let buffer = UnsafeMutableRawPointer(mutating: buf!.bytes).assumingMemoryBound(to: UInt8.self)
		let length = stream.read(buffer, maxLength: BUFFER_MAX)
		if length < 1 {
			return nil
		}
		return Data(bytes: buffer, count: length)
	}
	
	public func cleanup() {
		if let stream = inputStream {
			stream.delegate = nil
			CFReadStreamSetDispatchQueue(stream, nil)
			stream.close()
		}
		if let stream = outputStream {
			stream.delegate = nil
			CFWriteStreamSetDispatchQueue(stream, nil)
			stream.close()
		}
		outputStream = nil
		inputStream = nil
	}
	
	#if os(Linux) || os(watchOS)
	#else
	public func sslTrust() -> (trust: SecTrust?, domain: String?) {
		guard let outputStream = outputStream else { return (nil, nil) }
		
		let trust = outputStream.property(forKey: kCFStreamPropertySSLPeerTrust as Stream.PropertyKey) as! SecTrust?
		var domain = outputStream.property(forKey: kCFStreamSSLPeerName as Stream.PropertyKey) as! String?
		if domain == nil,
			let sslContextOut = CFWriteStreamCopyProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext? {
			var peerNameLen: Int = 0
			SSLGetPeerDomainNameLength(sslContextOut, &peerNameLen)
			var peerName = Data(count: peerNameLen)
			let _ = peerName.withUnsafeMutableBytes { (peerNamePtr: UnsafeMutablePointer<Int8>) in
				SSLGetPeerDomainName(sslContextOut, peerNamePtr, &peerNameLen)
			}
			if let peerDomain = String(bytes: peerName, encoding: .utf8), peerDomain.count > 0 {
				domain = peerDomain
			}
		}
		
		return (trust, domain)
	}
	#endif
	
	/**
	Delegate for the stream methods. Processes incoming bytes
	*/
	open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		if eventCode == .hasBytesAvailable {
			if aStream == inputStream {
				delegate?.newBytesInStream()
			}
		} else if eventCode == .errorOccurred {
			delegate?.streamDidError(error: aStream.streamError)
		} else if eventCode == .endEncountered {
			delegate?.streamDidError(error: nil)
		}
	}
}

#if canImport(Network)
import Network

@available(iOSApplicationExtension 12.0, iOS 12.0, OSXApplicationExtension 10.14, *)
open class NetworkStream : NSObject, WSStream  {
	private static let sharedWorkQueue = DispatchQueue(label: "com.vluxe.starscream.websocket", attributes: [])
	public weak var delegate: WSStreamDelegate?
	let BUFFER_MAX = 4096
	private var buffer = Data()
	
	public var enableSOCKSProxy = false
	
	private var connection: NWConnection?
	
	public func connect(url: URL, port: Int, timeout: TimeInterval, ssl: SSLSettings, completion: @escaping ((Error?) -> Void)) {
		let parameters: NWParameters
		if ssl.useSSL {
			parameters = .tls
		} else {
			parameters = .tcp
		}
		
		parameters.preferNoProxies = !enableSOCKSProxy
		
		
		let connection = NWConnection(
			host: NWEndpoint.Host(url.host!),
			port: NWEndpoint.Port(rawValue: UInt16(port))!,
			using: parameters
		)
		connection.stateUpdateHandler = { [weak self] newState in
			switch newState {
			case .ready:
				if self == nil {
					completion(WSError(type: .closeError, message: "socket object has been dereferenced", code: 0))
					return
				} else {
					completion(nil)
					self?._read()
				}
			case .failed(let error):
				completion(error)
			default:
				break
			}
		}
		connection.start(queue: NetworkStream.sharedWorkQueue)
		
		self.connection = connection
	}
	
	public func write(data: Data) -> Int {
		guard let connection = connection else { return -1 }
		connection.send(content: data, completion: .contentProcessed({ [weak self] error in
			if let error = error {
				self?.delegate?.streamDidError(error: error)
			}
		}))
		
		return data.count
	}
	
	private func _read() {
		guard let connection = connection else {return}
		
		connection.receive(minimumIncompleteLength: 0, maximumLength: BUFFER_MAX, completion: { [weak self] data, context, isComplete, error in
			if let data = data, error == nil {
				self?.buffer.append(data)
				self?.delegate?.newBytesInStream()
				
				// keep requesting more data until we are closed
				self?._read()
			} else {
				self?.delegate?.streamDidError(error: error)
			}
		})
	}
	
	public func read() -> Data? {
		let data = buffer
		buffer = Data()
		return data
	}
	
	public func cleanup() {
		connection?.cancel()
		connection = nil
	}
	
	#if os(Linux) || os(watchOS)
	#else
	public func sslTrust() -> (trust: SecTrust?, domain: String?) {
		// TODO: how do we handle this with Network.framework?
		return (nil, nil)

//		guard let connection = connection else { return (nil, nil) }
//
//		let trust = outputStream.property(forKey: kCFStreamPropertySSLPeerTrust as Stream.PropertyKey) as! SecTrust?
//		var domain = outputStream.property(forKey: kCFStreamSSLPeerName as Stream.PropertyKey) as! String?
//		if domain == nil,
//			let sslContextOut = CFWriteStreamCopyProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLContext)) as! SSLContext? {
//			var peerNameLen: Int = 0
//			SSLGetPeerDomainNameLength(sslContextOut, &peerNameLen)
//			var peerName = Data(count: peerNameLen)
//			let _ = peerName.withUnsafeMutableBytes { (peerNamePtr: UnsafeMutablePointer<Int8>) in
//				SSLGetPeerDomainName(sslContextOut, peerNamePtr, &peerNameLen)
//			}
//			if let peerDomain = String(bytes: peerName, encoding: .utf8), peerDomain.count > 0 {
//				domain = peerDomain
//			}
//		}
//
//		return (trust, domain)
	}
	#endif
}

public func defaultWSStream() -> WSStream {
	if #available(iOSApplicationExtension 12.0, iOS 12.0, OSXApplicationExtension 10.14, *) {
		return NetworkStream()
	} else {
		return FoundationStream()
	}
}
#else
public func defaultWSStream() -> WSStream {
	return FoundationStream()
}
#endif

