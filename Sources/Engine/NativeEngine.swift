//
//  NativeEngine.swift
//  Starscream
//
//  Created by Dalton Cherry on 6/15/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

//import Foundation
//
//@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
//public class NativeEngine: Engine {
//    private var task: URLSessionWebSocketTask?
//    weak var delegate: EngineDelegate?
//    
//    public init() {
//        //TODO: I probably need to drop down into the NWConnection APIs to get this to work with all of Starscream's features
//        //
//        //NOTE: URLSessionWebSocketTask doesn't work with our ruby web server in the SimpleTest example.
//        //It allows crashes. It works fine with https://echo.websocket.org in either http or https. Not sure why though
//        //needs more debugging and probably needs radar filed.
//    }
//
//    public func register(delegate: EngineDelegate) {
//        self.delegate = delegate
//    }
//
//    public func start(request: URLRequest) {
//        task = URLSession.shared.webSocketTask(with: request)
//        doRead()
//        task?.resume()
//    }
//
//    public func stop(closeCode: UInt16) {
//        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: Int(closeCode)) ?? .normalClosure
//        task?.cancel(with: closeCode, reason: nil)
//    }
//
//    public func forceStop() {
//        stop(closeCode: UInt16(URLSessionWebSocketTask.CloseCode.abnormalClosure.rawValue))
//    }
//
//    public func write(string: String, completion: (() -> ())?) {
//        task?.send(.string(string), completionHandler: { (error) in
//            completion?()
//        })
//    }
//
//    public func write(data: Data, opcode: FrameOpCode, completion: (() -> ())?) {
//        switch opcode {
//        case .binaryFrame:
//            task?.send(.data(data), completionHandler: { (error) in
//                completion?()
//            })
//        case .textFrame:
//            let text = String(data: data, encoding: .utf8)!
//            write(string: text, completion: completion)
//        case .ping:
//            task?.sendPing(pongReceiveHandler: { (error) in
//                completion?()
//            })
//        default:
//            break //unsupported
//        }
//    }
//
//    private func doRead() {
//        task?.receive { [weak self] (result) in
//            switch result {
//            case .success(let message):
//                switch message {
//                case .string(let string):
//                    self?.broadcast(event: .text(string))
//                case .data(let data):
//                    self?.broadcast(event: .binary(data))
//                @unknown default:
//                    break
//                }
//                break
//            case .failure(let error):
//                self?.broadcast(event: .error(error))
//            }
//            self?.doRead()
//        }
//    }
//
//    private func broadcast(event: WebSocketEvent) {
//        delegate?.didReceive(event: event)
//    }
//}
