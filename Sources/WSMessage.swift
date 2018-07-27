//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  WSMessageParser.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/25/18.
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




//  Processes and converts raw data into websocket frames
//  The messages

import Foundation
import SSCommonCrypto

struct WSMessage {
    let code: WebSocket.OpCode
    let data: Data
}

struct WSFrame {
    let code: WebSocket.OpCode
    let bytesLeft: Int
    let data: Data
}

protocol WSMessageParserDelegate: class {
    func didReceive(message: WSMessage)
    func didEncounter(error: WSError)
    func didParseHTTP(response: String)
}

protocol WSMessageParserClient {
    func append(data: Data)
    func createSendFrame(data: Data, code: WebSocket.OpCode) -> Data
    func reset()
}

class WSMessageParser: WSMessageParserClient {
    public weak var delegate: WSMessageParserDelegate?
    public var headerSecurityKey: String {
        return headerSecKey
    }
    
    struct CompressionState {
        var supportsCompression = false
        var messageNeedsDecompression = false
        var serverMaxWindowBits = 15
        var clientMaxWindowBits = 15
        var clientNoContextTakeover = false
        var serverNoContextTakeover = false
        var decompressor: Decompressor? = nil
        var compressor: Compressor? = nil
    }
    
    let FinMask: UInt8          = 0x80
    let OpCodeMask: UInt8       = 0x0F
    let RSVMask: UInt8          = 0x70
    let RSV1Mask: UInt8         = 0x40
    let MaskMask: UInt8         = 0x80
    let PayloadLenMask: UInt8   = 0x7F
    let httpSwitchProtocolCode  = 101
    let MaxFrameSize: Int       = 32
    
    private var inputQueue = [Data]()
    private var fragBuffer: Data?
    private let queue = DispatchQueue(label: "com.vluxe.starscream.messages", attributes: [])
    private var readStack = [WSFrame]()
    private let emptyBuffer = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
    private var didHandshake = false
    private var compressionState = CompressionState()
    private var headerSecKey = WSMessageParser.generateWebSocketKey()
    private let frameHeaderLength = MemoryLayout<UInt8>.size * 2
    
    // add the data to the queue to be processed
    func append(data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let process = self.inputQueue.count == 0
            self.inputQueue.append(data)
            if process {
                self.dequeue()
            }
        }
    }
    
    /// creates a websocket frame out of the data you wish to send to the WebSocket server
    func createSendFrame(data: Data, code: WebSocket.OpCode) -> Data {
        var offset = frameHeaderLength
        var firstByte: UInt8 = FinMask | code.rawValue
        var data = data
        if [.text, .binary].contains(code), let compressor = compressionState.compressor {
            do {
                data = try compressor.compress(data)
                if compressionState.clientNoContextTakeover {
                    try compressor.reset()
                }
                firstByte |= RSV1Mask
            } catch {
                //report error?  We can just send the uncompressed frame.
            }
        }
        let dataLength = data.count
        var dataBuffer = Data(capacity: dataLength + MaxFrameSize)
        
         let frame = dataBuffer.withUnsafeMutableBytes { (buffer: UnsafeMutablePointer<UInt8>) -> Data in
            buffer[0] = firstByte
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(UInt16.max) {
                buffer[1] = 126
                WSMessageParser.writeUint16(buffer, offset: offset, value: UInt16(dataLength))
                offset += MemoryLayout<UInt16>.size
            } else {
                buffer[1] = 127
                WSMessageParser.writeUint64(buffer, offset: offset, value: UInt64(dataLength))
                offset += MemoryLayout<UInt64>.size
            }
            buffer[1] |= MaskMask
            let maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
            _ = SecRandomCopyBytes(kSecRandomDefault, Int(MemoryLayout<UInt32>.size), maskKey)
            offset += MemoryLayout<UInt32>.size

            for i in 0..<dataLength {
                buffer[offset] = data[i] ^ maskKey[i % MemoryLayout<UInt32>.size]
                offset += 1
            }
            return Data(bytes: buffer, count: offset)
        }
        return frame
    }
    
    func reset() {
        queue.async { [weak self] in
            self?.didHandshake = false
        }
    }
    
    ///MARK: - parsing methods
    
    /// read from the input queue until it is empty
    private func dequeue() {
        while !inputQueue.isEmpty {
            autoreleasepool {
                let data = inputQueue.removeFirst()
                var work = data
                if let buffer = fragBuffer {
                    var combine = buffer
                    combine.append(data)
                    work = combine
                    fragBuffer = nil
                }
                let length = work.count
                work.withUnsafeBytes { (buffer: UnsafePointer<UInt8>) in
                    if !didHandshake {
                        processTCPHandshake(buffer, bufferLen: length)
                    } else {
                        processRawMessagesInBuffer(buffer, bufferLen: length)
                    }
                }
            }
        }
    }
    
    /// Process all messages in the buffer if possible.
    private func processRawMessagesInBuffer(_ pointer: UnsafePointer<UInt8>, bufferLen: Int) {
        var buffer = UnsafeBufferPointer(start: pointer, count: bufferLen)
        repeat {
            buffer = processOneRawMessage(inBuffer: buffer)
        } while buffer.count >= frameHeaderLength
        if buffer.count > 0 {
            fragBuffer = Data(buffer: buffer)
        }
    }
    
    /// process the raw data buffer and parse it into the websocket frames it represents
    private func processOneRawMessage(inBuffer buffer: UnsafeBufferPointer<UInt8>) -> UnsafeBufferPointer<UInt8> {
        guard let baseAddress = buffer.baseAddress else {return emptyBuffer}
        let bytesAvailable = buffer.count
    
        //need at least two bytes to know what kind of frame it is.
        if readStack.last != nil && bytesAvailable < frameHeaderLength {
            fragBuffer = Data(buffer: buffer)
            return emptyBuffer
        }
    
        //handle the current frame
        if let currentFrame = readStack.last, currentFrame.bytesLeft > 0 {
            var appendLength = currentFrame.bytesLeft
            var extraLength = bytesAvailable - currentFrame.bytesLeft
            
            //this frame still needs more content before it is full
            let isPartialFrame = currentFrame.bytesLeft > bytesAvailable
            if isPartialFrame {
                appendLength = bytesAvailable
                extraLength = 0 //update for the offset
            }

            //build buffer
            var combine = currentFrame.data
            combine.append(baseAddress, count: appendLength)
            
            _ = readStack.popLast()
            if isPartialFrame {
                readStack.append(WSFrame(code: currentFrame.code, bytesLeft: currentFrame.bytesLeft - appendLength, data: combine))
            } else {
                delegate?.didReceive(message: WSMessage(code: currentFrame.code, data: combine))
            }
            return buffer.fromOffset(bytesAvailable - extraLength)
        }
        
        //new frame!
        let isFin = (FinMask & baseAddress[0])
        let receivedOpcodeRawValue = (OpCodeMask & baseAddress[0])
        let receivedOpcode = WebSocket.OpCode(rawValue: receivedOpcodeRawValue)
        let isMasked = (MaskMask & baseAddress[1])
        let payloadLen = (PayloadLenMask & baseAddress[1])
        var offset = frameHeaderLength //skip past the control opcodes of the frame
        
        //validate the frame is proper frame
        if compressionState.supportsCompression && receivedOpcode != .continueFrame {
            compressionState.messageNeedsDecompression = (RSV1Mask & baseAddress[0]) > 0
        }
        
        if (isMasked > 0 || (RSVMask & baseAddress[0]) > 0) && receivedOpcode != .pong && !compressionState.messageNeedsDecompression {
            delegate?.didEncounter(error: WSError(type: .protocolError, message: "masked and rsv data is not currently supported", code: CloseCode.protocolError.rawValue))
            return emptyBuffer
        }
        let isControlFrame = (receivedOpcode == .connectionClose || receivedOpcode == .ping)
        if !isControlFrame && (receivedOpcode != .binary && receivedOpcode != .continueFrame &&
            receivedOpcode != .text && receivedOpcode != .pong) {
            delegate?.didEncounter(error: WSError(type: .protocolError, message: "unknown opcode: \(receivedOpcodeRawValue)", code: CloseCode.protocolError.rawValue))
            return emptyBuffer
        }
        if isControlFrame && isFin == 0 {
            delegate?.didEncounter(error: WSError(type: .protocolError, message: "control frames can't be fragmented", code: CloseCode.protocolError.rawValue))
            return emptyBuffer
        }
        
        //process the close code
        var closeCode = CloseCode.normal.rawValue
        if receivedOpcode == .connectionClose {
            if payloadLen == 1 {
                closeCode = CloseCode.protocolError.rawValue
            } else if payloadLen > 1 {
                closeCode = WSMessageParser.readUint16(baseAddress, offset: offset)
                if closeCode < 1000 || (closeCode > 1003 && closeCode < 1007) || (closeCode > 1013 && closeCode < 3000) {
                    closeCode = CloseCode.protocolError.rawValue
                }
            }
            if payloadLen < 2 {
                 delegate?.didEncounter(error: WSError(type: .expectedClose, message: "connection closed by server", code: closeCode))
                return emptyBuffer
            }
        } else if isControlFrame && payloadLen > 125 {
            delegate?.didEncounter(error: WSError(type: .protocolError, message: "control frame using extend payload", code: CloseCode.protocolError.rawValue))
            return emptyBuffer
        }
    
        //handle the "body" of the message
        var dataLength = UInt64(payloadLen)
        if dataLength == 127 {
            dataLength = WSMessageParser.readUint64(baseAddress, offset: offset)
            offset += MemoryLayout<UInt64>.size
        } else if dataLength == 126 {
            dataLength = UInt64(WSMessageParser.readUint16(baseAddress, offset: offset))
            offset += MemoryLayout<UInt16>.size
        }
        if bytesAvailable < offset || UInt64(bytesAvailable - offset) < dataLength {
            fragBuffer = Data(bytes: baseAddress, count: bytesAvailable)
            return emptyBuffer
        }
        var appendLength = dataLength
        if dataLength > UInt64(bytesAvailable) {
            appendLength = UInt64(bytesAvailable-offset)
        }
        if receivedOpcode == .connectionClose && appendLength > 0 {
            let size = MemoryLayout<UInt16>.size
            offset += size
            appendLength -= UInt64(size)
        }
        
        let data: Data
        if compressionState.messageNeedsDecompression, let decompressor = compressionState.decompressor {
            do {
                data = try decompressor.decompress(bytes: baseAddress+offset, count: Int(appendLength), finish: isFin > 0)
                if isFin > 0 && compressionState.serverNoContextTakeover {
                    try decompressor.reset()
                }
            } catch {
                delegate?.didEncounter(error: WSError(type: .protocolError, message: "Decompression failed: \(error)", code: CloseCode.protocolError.rawValue))
                return emptyBuffer
            }
        } else {
            data = Data(bytes: baseAddress+offset, count: Int(appendLength))
        }

        //handle frames by opcodes
        if receivedOpcode == .connectionClose {
            var closeReason = "connection closed by server"
            if let customCloseReason = String(data: data, encoding: .utf8) {
                closeReason = customCloseReason
            } else {
                closeCode = CloseCode.protocolError.rawValue
            }
            delegate?.didEncounter(error: WSError(type: .expectedClose, message: closeReason, code: closeCode))
            return emptyBuffer
        }
        if receivedOpcode == .pong || receivedOpcode == .ping {
            delegate?.didReceive(message: WSMessage(code: receivedOpcode!, data: data))
            return buffer.fromOffset(offset + Int(appendLength))
        }
        
        if let currentFrame = readStack.last {
            //handle "old" frame
            if receivedOpcode != .continueFrame {
                delegate?.didEncounter(error: WSError(type: .protocolError, message: "second and beyond of fragment message must be a continue frame", code: CloseCode.protocolError.rawValue))
                return emptyBuffer
            }
            var combine = currentFrame.data
            combine.append(data)
            _ = readStack.popLast()
            readStack.append(WSFrame(code: currentFrame.code, bytesLeft: currentFrame.bytesLeft - Int(appendLength), data: combine))
        } else {
            //handle new frame
            if receivedOpcode == .continueFrame {
                delegate?.didEncounter(error: WSError(type: .protocolError, message: "first frame can't be a continue frame", code: CloseCode.protocolError.rawValue))
                return emptyBuffer
            }
            let left = dataLength - appendLength
            readStack.append(WSFrame(code: receivedOpcode!, bytesLeft: Int(left), data: data))
        }
        
        //process response
        if let currentFrame = readStack.last, currentFrame.bytesLeft <= 0 && isFin > 0 {
            _ = readStack.popLast()
            delegate?.didReceive(message: WSMessage(code: currentFrame.code, data: currentFrame.data))
        }
        
        let step = Int(offset + numericCast(appendLength))
        return buffer.fromOffset(step)
    }
    
    ///MARK: - TCP/HTTP handling
    
    /// Handle checking the inital connection status
    private func processTCPHandshake(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        let code = processHTTP(buffer, bufferLen: bufferLen)
        switch code {
        case 0:
            break
        case -1:
            fragBuffer = Data(bytes: buffer, count: bufferLen)
        break // do nothing, we are going to collect more data
        default:
            delegate?.didEncounter(error: WSError(type: .upgradeError, message: "Invalid HTTP upgrade", code: UInt16(code)))
        }
    }
    
    /// Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
    private func processHTTP(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
        let CRLFBytes = [UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\n")]
        var k = 0
        var totalSize = 0
        for i in 0..<bufferLen {
            if buffer[i] == CRLFBytes[k] {
                k += 1
                if k == 4 {
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
            didHandshake = true
            let restSize = bufferLen - totalSize
            if restSize > 0 {
                processRawMessagesInBuffer(buffer + totalSize, bufferLen: restSize)
            }
            return 0 //success
        }
        return -1 // Was unable to find the full TCP header.
    }
    
    /// Validates the HTTP is a 101 as per the RFC spec.
    private func validateResponse(_ buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Int {
        guard let str = String(data: Data(bytes: buffer, count: bufferLen), encoding: .utf8) else { return -1 }
        let splitArr = str.components(separatedBy: "\r\n")
        var code = -1
        var i = 0
        var headers = [String: String]()
        for str in splitArr {
            if i == 0 {
                let responseSplit = str.components(separatedBy: .whitespaces)
                guard responseSplit.count > 1 else { return -1 }
                if let c = Int(responseSplit[1]) {
                    code = c
                }
            } else {
                let responseSplit = str.components(separatedBy: ":")
                guard responseSplit.count > 1 else { break }
                let key = responseSplit[0].trimmingCharacters(in: .whitespaces)
                let val = responseSplit[1].trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = val
            }
            i += 1
        }
    
        if code != httpSwitchProtocolCode {
            return code
        }
        
        if let extensionHeader = headers[WebSocket.headerWSExtensionName.lowercased()] {
            processExtensionHeader(extensionHeader)
        }
        
        if let acceptKey = headers[WebSocket.headerWSAcceptName.lowercased()] {
            if acceptKey.count > 0 {
                if headerSecKey.count > 0 {
                    let sha = "\(headerSecKey)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".sha1Base64()
                    if sha != acceptKey as String {
                        return -1
                    }
                }
                delegate?.didParseHTTP(response: str)
                return 0
            }
        }
        return -1
    }
    

    /// Parses the extension header, setting up the compression parameters.
    func processExtensionHeader(_ extensionHeader: String) {
        let parts = extensionHeader.components(separatedBy: ";")
        for p in parts {
            let part = p.trimmingCharacters(in: .whitespaces)
            if part == "permessage-deflate" {
                compressionState.supportsCompression = true
            } else if part.hasPrefix("server_max_window_bits=") {
                let valString = part.components(separatedBy: "=")[1]
                if let val = Int(valString.trimmingCharacters(in: .whitespaces)) {
                    compressionState.serverMaxWindowBits = val
                }
            } else if part.hasPrefix("client_max_window_bits=") {
                let valString = part.components(separatedBy: "=")[1]
                if let val = Int(valString.trimmingCharacters(in: .whitespaces)) {
                    compressionState.clientMaxWindowBits = val
                }
            } else if part == "client_no_context_takeover" {
                compressionState.clientNoContextTakeover = true
            } else if part == "server_no_context_takeover" {
                compressionState.serverNoContextTakeover = true
            }
        }
        if compressionState.supportsCompression {
            compressionState.decompressor = Decompressor(windowBits: compressionState.serverMaxWindowBits)
            compressionState.compressor = Compressor(windowBits: compressionState.clientMaxWindowBits)
        }
    }
    
    /// Generate a WebSocket key as needed in RFC.
    static func generateWebSocketKey() -> String {
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
    
    /// Read a 16 bit big endian value from a buffer
    private static func readUint16(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt16 {
        return (UInt16(buffer[offset + 0]) << 8) | UInt16(buffer[offset + 1])
    }
    
    /// Read a 64 bit big endian value from a buffer
    private static func readUint64(_ buffer: UnsafePointer<UInt8>, offset: Int) -> UInt64 {
        var value = UInt64(0)
        for i in 0...7 {
            value = (value << 8) | UInt64(buffer[offset + i])
        }
        return value
    }
    
    /// Write a 16-bit big endian value to a buffer.
    static func writeUint16(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt16) {
        buffer[offset + 0] = UInt8(value >> 8)
        buffer[offset + 1] = UInt8(value & 0xff)
    }
    
    /// Write a 64-bit big endian value to a buffer.
    private static func writeUint64(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int, value: UInt64) {
        for i in 0...7 {
            buffer[offset + i] = UInt8((value >> (8*UInt64(7 - i))) & 0xff)
        }
    }
}

extension UnsafeBufferPointer {
    func fromOffset(_ offset: Int) -> UnsafeBufferPointer<Element> {
        return UnsafeBufferPointer<Element>(start: baseAddress?.advanced(by: offset), count: count - offset)
    }
}

private extension String {
    func sha1Base64() -> String {
        let data = self.data(using: String.Encoding.utf8)!
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0, CC_LONG(data.count), &digest) }
        return Data(bytes: digest).base64EncodedString()
    }
}
