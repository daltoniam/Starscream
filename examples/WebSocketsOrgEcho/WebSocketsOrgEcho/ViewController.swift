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
    func websocketIsWaitingForConnectivity(socket: WebSocketClient) {
        
    }
    
    func websocket(_ socket: WebSocketClient, isPathViable: Bool) {
        
    }
    
    func websocket(_ socket: WebSocketClient, isBetterPathAvailable: Bool) {
        
    }
    
    
//    var socket: WebSocket = WebSocket(url: URL(staticString: "wss://echo.websocket.org"), stream: NetworkStream())
    var socket: WebSocket = WebSocket(url: URL(staticString: "wss://echo.websocket.org"))
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("websocketDidConnect")
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("websocketDidDisconnect", error ?? "")
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
        socket.connect()
    }
}
