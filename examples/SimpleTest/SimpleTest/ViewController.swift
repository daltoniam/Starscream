//
//  ViewController.swift
//  SimpleTest
//
//  Created by Dalton Cherry on 8/12/14.
//  Copyright (c) 2014 vluxe. All rights reserved.
//

import UIKit

var socket = Websocket(url: NSURL.URLWithString("ws://localhost:8080"))

class ViewController: UIViewController, WebsocketDelegate {
                            
    override func viewDidLoad() {
        super.viewDidLoad()
        socket.delegate = self
        socket.connect()
    }
    
    //websocket delegate methods
    
    func websocketDidConnect() {
        println("websocket is connected")
    }
    func websocketDidDisconnect(error: NSError?) {
        println("websocket is disconnected: \(error!.localizedDescription)")
    }
    func websocketDidWriteError(error: NSError?) {
        println("wez got an error from the websocket: \(error!.localizedDescription)")
    }
    func websocketDidReceiveMessage(text: String) {
        println("got some text: \(text)")
        //self.socket.writeString(text) //example on how to write a string the socket
    }
    func websocketDidReceiveData(data: NSData) {
        println("got some data: \(data.length)")
        //self.socket.writeData(data) //example on how to write binary data to the socket
    }
    //write something to the socket
    @IBAction func writeText(sender: UIBarButtonItem) {
        socket.writeString("hello there!")
    }

}

