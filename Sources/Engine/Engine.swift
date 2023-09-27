//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Engine.swift
//  Starscream
//
//  Created by Dalton Cherry on 6/15/19
//  Copyright © 2019 Vluxe. All rights reserved.
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

public protocol EngineDelegate: AnyObject {
    func didReceive(event: WebSocketEvent)
}

public protocol Engine {
    func register(delegate: EngineDelegate)
    func start(request: URLRequest)
    func stop(closeCode: UInt16)
    func forceStop()
    func write(data: Data, opcode: FrameOpCode, completion: (() -> ())?)
    func write(string: String, completion: (() -> ())?)
}
