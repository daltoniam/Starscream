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
    var socket = WebSocket(url: NSURL(string: "ws://localhost:8080/")!, protocols: ["chat", "superchat"])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        socket.delegate = self
        socket.connect()
    }
    
    // MARK: Websocket Delegate Methods.
    
    func websocketDidConnect(ws: WebSocket) {
        print("websocket is connected")
    }
    
    func websocketDidDisconnect(ws: WebSocket, error: NSError?) {
        if let e = error {
            print("websocket is disconnected: \(e.localizedDescription)")
        } else {
             print("websocket disconnected")
        }
    }
    
    func websocketDidReceiveMessage(ws: WebSocket, text: String) {
        print("Received text: \(text)")
    }
    
    func websocketDidReceiveData(ws: WebSocket, data: NSData) {
        print("Received data: \(data.length)")
    }
    
    // MARK: Write Text Action
    
    @IBAction func writeText(sender: UIBarButtonItem) {
        socket.writeString("hello there!")
    }
    
    // MARK: Disconnect Action
    
    @IBAction func disconnect(sender: UIBarButtonItem) {
        if socket.isConnected {
            sender.title = "Connect"
            socket.disconnect()
        } else {
            sender.title = "Disconnect"
            socket.connect()
        }
    }
    
}

