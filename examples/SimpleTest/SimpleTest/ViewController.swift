//
//  ViewController.swift
//  SimpleTest
//
//  Created by Dalton Cherry on 8/12/14.
//  Copyright (c) 2014 vluxe. All rights reserved.
//

import UIKit
import Starscream

class ViewController: UIViewController, WebsocketDelegate {
    var socket = Websocket(url: NSURL(scheme: "ws", host: "localhost:8080", path: "/"))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        socket.delegate = self
        socket.connect()
    }
    
    // MARK: Websocket Delegate Methods.
    
    func websocketDidConnect() {
        println("websocket is connected")
    }
    
    func websocketDidDisconnect(error: NSError?) {
        if let e = error {
            println("websocket is disconnected: \(e.localizedDescription)")
        }
    }
    
    func websocketDidWriteError(error: NSError?) {
        if let e = error {
            println("wez got an error from the websocket: \(e.localizedDescription)")
        }
    }
    
    func websocketDidReceiveMessage(text: String) {
        println("Received text: \(text)")
    }
    
    func websocketDidReceiveData(data: NSData) {
        println("Received data: \(data.length)")
    }
    
    // MARK: Write Text Action
    
    @IBAction func writeText(sender: UIBarButtonItem) {
        socket.writeString("hello there!")
    }

}

