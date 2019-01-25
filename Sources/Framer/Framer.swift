//
//  Framer.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

let FinMask: UInt8          = 0x80
let OpCodeMask: UInt8       = 0x0F
let RSVMask: UInt8          = 0x70
let RSV1Mask: UInt8         = 0x40
let MaskMask: UInt8         = 0x80
let PayloadLenMask: UInt8   = 0x7F

public enum FrameOpCode: UInt8 {
    case continueFrame = 0x0
    case textFrame = 0x1
    case binaryFrame = 0x2
    // 3-7 are reserved.
    case connectionClose = 0x8
    case ping = 0x9
    case pong = 0xA
    // B-F reserved.
    case unknown = 100
}

public struct Frame {
    let isFin: Bool
    let RSV1: Bool
    let isMasked: Bool
    let opcode: FrameOpCode
    let payloadLength: UInt64
    let payload: Data
}

public enum FrameEvent {
    case frame(Frame)
    case error(Error)
}

public protocol FramerEventClient: class {
    func frameProcessed(event: FrameEvent)
}

public protocol Framer {
    func add(data: Data)
    func register(delegate: FramerEventClient)
}

public class WSFramer: Framer {
    private let queue = DispatchQueue(label: "com.vluxe.starscream.wsframer", attributes: [])
    private weak var delegate: FramerEventClient?
    private var buffer = Data()
    private let supportsCompression = false //TODO: setup in init
    
    enum ProcessEvent {
        case needsMoreData
        case processedFrame(Frame, Int)
        case failed(Error)
    }
    
    public func add(data: Data) {
        queue.async { [weak self] in
            self?.buffer.append(data)
            while(true) {
               let event = self?.process() ?? .needsMoreData
                switch event {
                case .needsMoreData:
                    return
                case .processedFrame(let frame, let split):
                    guard let s = self else { return }
                    s.buffer = s.buffer.advanced(by: split)
                    s.delegate?.frameProcessed(event: .frame(frame))
                case .failed(let error):
                    self?.delegate?.frameProcessed(event: .error(error))
                    self?.buffer = Data()
                    return
                }
            }
        }
    }

    public func register(delegate: FramerEventClient) {
        self.delegate = delegate
    }
    
    private func process() -> ProcessEvent {
        if buffer.count < 2 {
            return .needsMoreData
        }
        let pointer = buffer.withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: buffer.count))
        }
        let isFin = (FinMask & pointer[0])
        let opcodeRawValue = (OpCodeMask & pointer[0])
        let opcode = FrameOpCode(rawValue: opcodeRawValue) ?? .unknown
        let isMasked = (MaskMask & pointer[1])
        let payloadLen = (PayloadLenMask & pointer[1])
        let RSV1 = (RSVMask & pointer[0])
        var needsDecompression = false
        
        if supportsCompression && opcode != .continueFrame {
           needsDecompression = (RSV1Mask & pointer[0]) > 0
        }
        if (isMasked > 0 || RSV1 > 0) && opcode != .pong && !needsDecompression {
            let errCode = CloseCode.protocolError.rawValue
            return .failed(WSError(type: .protocolError, message: "masked and rsv data is not currently supported", code: Int(errCode)))
        }
        let isControlFrame = (opcode == .connectionClose || opcode == .ping)
        if !isControlFrame && (opcode != .binaryFrame && opcode != .continueFrame &&
            opcode != .textFrame && opcode != .pong) {
            let errCode = CloseCode.protocolError.rawValue
            return .failed(WSError(type: .protocolError, message: "unknown opcode: \(opcodeRawValue)", code: Int(errCode)))
        }
        if isControlFrame && isFin == 0 {
            let errCode = CloseCode.protocolError.rawValue
            return .failed(WSError(type: .protocolError, message: "control frames can't be fragmented", code: Int(errCode)))
        }
        
        var offset = 2
        var closeCode = CloseCode.normal.rawValue
        if opcode == .connectionClose {
            if payloadLen == 1 {
                closeCode = CloseCode.protocolError.rawValue
            } else if payloadLen > 1 {
                closeCode = readUint16(pointer, offset: offset)
                if closeCode < 1000 || (closeCode > 1003 && closeCode < 1007) || (closeCode > 1013 && closeCode < 3000) {
                    closeCode = CloseCode.protocolError.rawValue
                }
            }
            return .failed(WSError(type: .protocolError, message: "connection closed by server", code: Int(closeCode)))
        } else if isControlFrame && payloadLen > 125 {
            return .failed(WSError(type: .protocolError, message: "payload length is longer than allowed for a control frame", code: Int(CloseCode.protocolError.rawValue)))
        }
        
        var dataLength = UInt64(payloadLen)
        if payloadLen == 127 {
            dataLength = readUint64(pointer, offset: offset)
            offset += MemoryLayout<UInt64>.size
        } else if payloadLen == 126 {
            dataLength = UInt64(readUint16(pointer, offset: offset))
            offset += MemoryLayout<UInt16>.size
        }
        
        if dataLength > (pointer.count - offset) {
            return .needsMoreData
        }
        //I don't like this cast, but Data's count returns an Int.
        //Might be a problem with huge payloads. Need to revisit.
        let readDataLength = Int(dataLength)
        
        let payload = Data(bytes: pointer[offset...readDataLength])
        offset += readDataLength

        let frame = Frame(isFin: isFin > 0, RSV1: RSV1 > 0, isMasked: isMasked > 0, opcode: opcode, payloadLength: dataLength, payload: payload)
        return .processedFrame(frame, offset)
    }
    
    private func readUint16(_ buffer: [UInt8], offset: Int) -> UInt16 {
        return (UInt16(buffer[offset + 0]) << 8) | UInt16(buffer[offset + 1])
    }
    
    private func readUint64(_ buffer: [UInt8], offset: Int) -> UInt64 {
        var value = UInt64(0)
        for i in 0...7 {
            value = (value << 8) | UInt64(buffer[offset + i])
        }
        return value
    }

}
