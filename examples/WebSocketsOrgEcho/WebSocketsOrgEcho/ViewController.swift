//
//  ViewController.swift
//  WebSocketsOrgEcho
//
//  Created by Kristaps Grinbergs on 08/10/2018.
//  Copyright © 2018 Starscream. All rights reserved.
//

import UIKit

import Starscream

class ViewController: UIViewController, WebSocketDelegate {

    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var helloButton: UIButton!

    var socket: WebSocket = WebSocket(url: URL(staticString: "wss://echo.websocket.org"))
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("websocketDidConnect")
        connectButton.setTitle("Disconnect", for: .normal)
        helloButton.isEnabled = true
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("websocketDidDisconnect", error ?? "")
        connectButton.setTitle("Connect", for: .normal)
        helloButton.isEnabled = false
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("websocketDidReceiveMessage", text)
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("websocketDidReceiveData", data)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        socket.delegate = self
    }
    
    @IBAction func connect(_ sender: Any) {
        if socket.isConnected {
            socket.disconnect()
        } else {
            socket.connect()
        }
    }

    @IBAction func hello(_ sender: Any) {
        socket.write(string: "Hello")
    }
}
