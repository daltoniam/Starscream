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
    
    let host = "localhost:9001"
    let scheme = "ws"
    var socketArray = [WebSocket]()
    var caseCount = 300 //starting cases
    override func viewDidLoad() {
        super.viewDidLoad()
        getCaseCount()
        //getTestInfo(1)
    }
    
    func removeSocket(s: WebSocket) {
        self.socketArray = self.socketArray.filter{$0 != s}
    }
    
    func getCaseCount() {
        let s = WebSocket(url: NSURL(scheme: scheme, host: host, path: "/getCaseCount")!, protocols: [])
        socketArray.append(s)
        s.onText = {[unowned self] (text: String) in
            if let c = Int(text) {
                print("number of cases is: \(c)")
                self.caseCount = c
            }
        }
        s.onDisconnect = {[unowned self] (error: NSError?) in
            self.getTestInfo(1)
            self.removeSocket(s)
        }
        s.connect()
    }
    
    func getTestInfo(caseNum: Int) {
        let s = createSocket("getCaseInfo",caseNum)
        socketArray.append(s)
        s.onText = {(text: String) in
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
        s.onDisconnect = {[unowned self] (error: NSError?) in
            if !once {
                once = true
                self.runTest(caseNum)
            }
            self.removeSocket(s)
        }
        s.connect()
    }
    
    func runTest(caseNum: Int) {
        let s = createSocket("runCase",caseNum)
        self.socketArray.append(s)
        s.onText = {(text: String) in
            s.writeString(text)
        }
        s.onData = {(data: NSData) in
            s.writeData(data)
        }
        var once = false
        s.onDisconnect = {[unowned self] (error: NSError?) in
            if !once {
                once = true
                print("case:\(caseNum) finished")
                self.verifyTest(caseNum)
                self.removeSocket(s)
            }
        }
        s.connect()
    }
    
    func verifyTest(caseNum: Int) {
        let s = createSocket("getCaseStatus",caseNum)
        self.socketArray.append(s)
        s.onText = {(text: String) in
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
        s.onDisconnect = {[unowned self] (error: NSError?) in
            if !once {
                once = true
                let nextCase = caseNum+1
                if nextCase <= self.caseCount {
                    self.getTestInfo(nextCase)
                } else {
                    self.finishReports()
                }
            }
            self.removeSocket(s)
        }
        s.connect()
    }
    
    func finishReports() {
        let s = createSocket("updateReports",0)
        self.socketArray.append(s)
        s.onDisconnect = {[unowned self] (error: NSError?) in
            print("finished all the tests!")
            self.removeSocket(s)
        }
        s.connect()
    }
    
    func createSocket(cmd: String, _ caseNum: Int) -> WebSocket {
        return WebSocket(url: NSURL(scheme: scheme,
            host: host, path: buildPath(cmd,caseNum))!, protocols: [])
    }
    
    func buildPath(cmd: String, _ caseNum: Int) -> String {
        return "/\(cmd)?case=\(caseNum)&agent=Starscream"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

