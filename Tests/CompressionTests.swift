//
//  CompressionTests.swift
//  Starscream
//
//  Created by Joseph Ross on 5/23/17.
//  Copyright © 2017 Vluxe. All rights reserved.
//

import XCTest

class CompressionTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testBasic() {
        let compressor = Compressor(windowBits: 15)!
        let decompressor = Decompressor(windowBits: 15)!
        
        let rawData = "Hello, World! Hello, World! Hello, World! Hello, World! Hello, World!".data(using: .utf8)!
        
        let compressed = try! compressor.compress(rawData)
        let uncompressed = try! decompressor.decompress(compressed, finish: true)
        
        XCTAssert(rawData == uncompressed)
    }
    
    func testHugeData() {
        let compressor = Compressor(windowBits: 15)!
        let decompressor = Decompressor(windowBits: 15)!
        
        // 2 Gigs!
//        var rawData = Data(repeating: 0, count: 0x80000000)
        var rawData = Data(repeating: 0, count: 0x80000)
        rawData.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<UInt8>) -> Void in
            arc4random_buf(ptr, rawData.count)
        }
        
        let compressed = try! compressor.compress(rawData)
        let uncompressed = try! decompressor.decompress(compressed, finish: true)
        
        XCTAssert(rawData == uncompressed)
    }
    
}
