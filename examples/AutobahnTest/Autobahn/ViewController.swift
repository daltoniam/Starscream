//
//  ViewController.swift
//  Autobahn
//
//  Created by Dalton Cherry on 7/24/15.
//  Copyright (c) 2015 vluxe. All rights reserved.
//

import UIKit
import Starscream

class ViewController: UIViewController {
    
    static let host = "localhost:9001"
    static let scheme = "ws"
    var socket = WebSocket(url: NSURL(scheme: scheme, host: host, path: "/getCaseCount")!, protocols: [])
    var caseCount = 300 //starting cases
    override func viewDidLoad() {
        super.viewDidLoad()
        getCaseCount()
        //getTestInfo(1)
    }
    
    func getCaseCount() {
        socket.onText = {(text: String) in
            if let c = Int(text) {
                print("number of cases is: \(c)")
                self.caseCount = c
            }
        }
        socket.onDisconnect = {(error: NSError?) in
            self.getTestInfo(1)
        }
        socket.connect()
    }
    
    func getTestInfo(caseNum: Int) {
        socket = createSocket("getCaseInfo",caseNum)
        socket.onText = {(text: String) in
//            let data = text.dataUsingEncoding(NSUTF8StringEncoding)
//            do {
//                let resp: AnyObject? = try NSJSONSerialization.JSONObjectWithData(data!,
//                    options: NSJSONReadingOptions())
//                if let dict = resp as? Dictionary<String,String> {
//                    let num = dict["id"]
//                    let summary = dict["description"]
//                    if let n = num, let sum = summary {
//                        print("running case:\(caseNum) id:\(n) summary: \(sum)")
//                    }
//                }
//            } catch {
//                print("error parsing the json")
//            }

        }
        var once = false
        socket.onDisconnect = {(error: NSError?) in
            if !once {
                once = true
                self.runTest(caseNum)
            }
        }
        socket.connect()
    }
    
    func runTest(caseNum: Int) {
        socket = createSocket("runCase",caseNum)
        socket.onText = {(text: String) in
            self.socket.writeString(text)
        }
        socket.onData = {(data: NSData) in
            self.socket.writeData(data)
        }
        var once = false
        socket.onDisconnect = {(error: NSError?) in
            if !once {
                once = true
                print("case:\(caseNum) finished")
                self.verifyTest(caseNum)
            }
        }
        socket.connect()
    }
    
    func verifyTest(caseNum: Int) {
        socket = createSocket("getCaseStatus",caseNum)
        socket.onText = {(text: String) in
            let data = text.dataUsingEncoding(NSUTF8StringEncoding)
            do {
                let resp: AnyObject? = try NSJSONSerialization.JSONObjectWithData(data!,
                    options: NSJSONReadingOptions())
                if let dict = resp as? Dictionary<String,String> {
                    if let status = dict["behavior"] {
                        if status == "OK" {
                            print("SUCCESS: \(caseNum)")
                            return
                        }
                    }
                    print("FAILURE: \(caseNum)")
                }
            } catch {
               print("error parsing the json")
            }
        }
        var once = false
        socket.onDisconnect = {(error: NSError?) in
            if !once {
                once = true
                let nextCase = caseNum+1
                if nextCase <= self.caseCount {
                    self.getTestInfo(nextCase)
                } else {
                    self.finishReports()
                }
            }
        }
        socket.connect()
    }
    
    func finishReports() {
        socket = createSocket("updateReports",0)
        socket.onDisconnect = {(error: NSError?) in
            print("finished all the tests!")
        }
        socket.connect()
    }
    
    func createSocket(cmd: String, _ caseNum: Int) -> WebSocket {
        return WebSocket(url: NSURL(scheme: ViewController.scheme,
            host: ViewController.host, path: buildPath(cmd,caseNum))!, protocols: [])
    }
    
    func buildPath(cmd: String, _ caseNum: Int) -> String {
        return "/\(cmd)?case=\(caseNum)&agent=Starscream"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

