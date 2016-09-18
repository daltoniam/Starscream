//
//  ViewController.swift
//  SimpleTest
//
//  Created by Dalton Cherry on 8/12/14.
//  Copyright (c) 2014 vluxe. All rights reserved.
//

import UIKit
import Starscream

class ViewController: UIViewController, WebSocketDelegate {
    var socket = WebSocket(url: URL(string: "ws://localhost:8080/")!, protocols: ["chat", "superchat"])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        socket.delegate = self
        socket.connect()
    }
    
    // MARK: Websocket Delegate Methods.
    
    func websocketDidConnect(socket: WebSocket) {
        print("websocket is connected")
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        if let e = error {
            print("websocket is disconnected: \(e.localizedDescription)")
        } else {
             print("websocket disconnected")
        }
    }
    
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        print("Received text: \(text)")
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: Data) {
        print("Received data: \(data.count)")
    }
    
    // MARK: Write Text Action
    
    @IBAction func writeText(_ sender: UIBarButtonItem) {
        socket.write(string: "hello there!")
    }
    
    // MARK: Disconnect Action
    
    @IBAction func disconnect(_ sender: UIBarButtonItem) {
        if socket.isConnected {
            sender.title = "Connect"
            socket.disconnect()
        } else {
            sender.title = "Disconnect"
            socket.connect()
        }
    }
    
}

