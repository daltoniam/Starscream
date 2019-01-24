//
//  FrameCollector.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/24/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

import Foundation

public protocol FrameCollectorDelegate: class {
    func didForm(event: FrameCollector.Event)
}

public class FrameCollector {
    public enum Event {
        case text(String)
        case binary(Data)
        case pong(Data)
        case ping(Data)
        case error(Error)
    }
    weak var delegate: FrameCollectorDelegate?
    var collect = [Frame]()
    
    public func add(frame: Frame) {
        collect.append(frame)
        //TODO: sanity checks here...
    }
}
