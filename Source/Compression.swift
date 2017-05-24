//
//  Compression.swift
//  Starscream
//
//  Created by Joseph Ross on 5/23/17.
//  Copyright © 2017 Vluxe. All rights reserved.
//

import Foundation

private let ZLIB_VERSION = Array("1.2.8".utf8CString)

private let Z_OK:CInt = 0
private let Z_BUF_ERROR:CInt = -5

private let Z_SYNC_FLUSH:CInt = 2

class Decompressor {
    private var strm = z_stream()
    private var buffer = [UInt8](repeating: 0, count: 0x2000)
    private var inflateInitialized = false
    private let windowBits:Int
    
    init?(windowBits:Int) {
        self.windowBits = windowBits
        guard initInflate() else { return nil }
    }
    
    private func initInflate() -> Bool {
        if Z_OK == inflateInit2(strm: &strm, windowBits: -CInt(windowBits),
                                version: ZLIB_VERSION, streamSize: CInt(MemoryLayout<z_stream>.size))
        {
            inflateInitialized = true
            return true
        }
        return false
    }
    
    func reset() throws {
        teardownInflate()
        guard initInflate() else { throw NSError() }
    }
    
    func decompress(_ data: Data, finish: Bool) throws -> Data {
        let data = data
        let tail = Data([0x00, 0x00, 0xFF, 0xFF])
        
        var decompressed = Data()
        
        try decompress(in: data, out: &decompressed)
        if finish { try decompress(in: tail, out: &decompressed) }
        
        return decompressed
        
    }
    
    private func decompress(in data: Data, out:inout Data) throws {
        var res:CInt = 0
        data.withUnsafeBytes { (ptr:UnsafePointer<UInt8>) -> Void in
            strm.next_in = ptr
            strm.avail_in = CUnsignedInt(data.count)
            
            repeat {
                strm.next_out = UnsafeMutablePointer<UInt8>(&buffer)
                strm.avail_out = CUnsignedInt(buffer.count)
                
                res = inflate(strm: &strm, flush: 0)
                
                let byteCount = buffer.count - Int(strm.avail_out)
                out.append(buffer, count: byteCount)
            } while res == Z_OK && strm.avail_out == 0
            
        }
        guard (res == Z_OK && strm.avail_out > 0)
            || (res == Z_BUF_ERROR && Int(strm.avail_out) == buffer.count)
            else {
                throw NSError()//"Error during inflate: \(res)")
        }
    }
    
    private func teardownInflate() {
        if inflateInitialized, Z_OK == inflateEnd(strm: &strm) {
            inflateInitialized = false
        }
    }
    
    deinit {
        teardownInflate()
    }
    
    @_silgen_name("inflateInit2_") private func inflateInit2(strm: UnsafeMutableRawPointer, windowBits: CInt,
                                                    version: UnsafePointer<CChar>, streamSize: CInt) -> CInt
    @_silgen_name("inflate") private func inflate(strm: UnsafeMutableRawPointer, flush: CInt) -> CInt
    @discardableResult
    @_silgen_name("inflateEnd") private func inflateEnd(strm: UnsafeMutableRawPointer) -> CInt
}

class Compressor {
    private var strm = z_stream()
    private var buffer = [UInt8](repeating: 0, count: 0x2000)
    private var deflateInitialized = false
    private let windowBits:Int
    
    init?(windowBits: Int) {
        self.windowBits = windowBits
        guard initDeflate() else { return nil }
    }
    
    private func initDeflate() -> Bool {
        if Z_OK == deflateInit2(strm: &strm, level: Z_DEFAULT_COMPRESSION, method: Z_DEFLATED,
                                windowBits: -CInt(windowBits), memLevel: 8, strategy: Z_DEFAULT_STRATEGY,
                                version: ZLIB_VERSION, streamSize: CInt(MemoryLayout<z_stream>.size))
        {
            deflateInitialized = true
            return true
        }
        return false
    }
    
    func reset() throws {
        teardownDeflate()
        guard initDeflate() else { throw NSError() }
    }
    
    func compress(_ data: Data) throws -> Data {
        var compressed = Data()
        var res:CInt = 0
        data.withUnsafeBytes { (ptr:UnsafePointer<UInt8>) -> Void in
            strm.next_in = ptr
            strm.avail_in = CUnsignedInt(data.count)
            
            repeat {
                strm.next_out = UnsafeMutablePointer<UInt8>(&buffer)
                strm.avail_out = CUnsignedInt(buffer.count)
                
                res = deflate(strm: &strm, flush: Z_SYNC_FLUSH)
                
                let byteCount = buffer.count - Int(strm.avail_out)
                compressed.append(buffer, count: byteCount)
            }
            while res == Z_OK && strm.avail_out == 0
                
        }
        
        guard res == Z_OK && strm.avail_out > 0
            || (res == Z_BUF_ERROR && Int(strm.avail_out) == buffer.count)
        else {
            NSLog("Error during deflate: \(res)")
            throw NSError()
        }
        
        compressed.removeLast(4)
        return compressed
    }
    
    private func teardownDeflate() {
        if deflateInitialized, Z_OK == deflateEnd(strm: &strm) {
            deflateInitialized = false
        }
    }
    
    deinit {
        teardownDeflate()
    }
    
    @_silgen_name("deflateInit2_") private func deflateInit2(strm: UnsafeMutableRawPointer, level: CInt, method: CInt,
                                                     windowBits: CInt, memLevel: CInt, strategy: CInt,
                                                     version: UnsafePointer<CChar>, streamSize: CInt) -> CInt
    @_silgen_name("deflate") private func deflate(strm: UnsafeMutableRawPointer, flush: CInt) -> CInt
    @discardableResult
    @_silgen_name("deflateEnd") private func deflateEnd(strm: UnsafeMutableRawPointer) -> CInt
    
    private let Z_DEFAULT_COMPRESSION:CInt = -1
    private let Z_DEFLATED:CInt = 8
    private let Z_DEFAULT_STRATEGY:CInt = 0
}

private struct z_stream {
    var next_in: UnsafePointer<UInt8>? = nil            /* next input byte */
    var avail_in: CUnsignedInt = 0                      /* number of bytes available at next_in */
    var total_in: CUnsignedLong = 0                     /* total number of input bytes read so far */
    
    var next_out: UnsafeMutablePointer<UInt8>? = nil    /* next output byte should be put there */
    var avail_out: CUnsignedInt = 0                     /* remaining free space at next_out */
    var total_out: CUnsignedLong = 0                    /* total number of bytes output so far */
    
    var msg: UnsafePointer<CChar>? = nil                /* last error message, NULL if no error */
    private var state: OpaquePointer? = nil             /* not visible by applications */
    
    private var zalloc: OpaquePointer? = nil            /* used to allocate the internal state */
    private var zfree: OpaquePointer? = nil             /* used to free the internal state */
    private var opaque: OpaquePointer? = nil            /* private data object passed to zalloc and zfree */
    
    var data_type: CInt = 0                             /* best guess about the data type: binary or text */
    var adler: CUnsignedLong = 0                        /* adler32 value of the uncompressed data */
    private var reserved: CUnsignedLong = 0             /* reserved for future use */
}

