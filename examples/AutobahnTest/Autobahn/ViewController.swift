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
    var socketArray = [WebSocket]()
    var caseCount = 300 //starting cases
    override func viewDidLoad() {
        super.viewDidLoad()
        getCaseCount()
        //getTestInfo(1)
    }
    
    func removeSocket(_ s: WebSocket?) {
        socketArray = socketArray.filter{$0 != s}
    }
    
    func getCaseCount() {
        
        let s = WebSocket(url: URL(string: "ws://\(host)/getCaseCount")!, protocols: [])
        socketArray.append(s)
        s.onText = { [weak self]  (text: String) in
            if let c = Int(text) {
                print("number of cases is: \(c)")
                self?.caseCount = c
            }
        }
        s.onDisconnect = { [weak self, weak s]  (error: Error?) in
            self?.getTestInfo(1)
            self?.removeSocket(s)
        }
        s.connect()
    }
    
    func getTestInfo(_ caseNum: Int) {
        let s = createSocket("getCaseInfo",caseNum)
        socketArray.append(s)
        s.onText = { (text: String) in
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
        s.onDisconnect = { [weak self, weak s]  (error: Error?) in
            if !once {
                once = true
                self?.runTest(caseNum)
            }
            self?.removeSocket(s)
        }
        s.connect()
    }
    
    func runTest(_ caseNum: Int) {
        let s = createSocket("runCase",caseNum)
        self.socketArray.append(s)
        s.onText = { [weak s]  (text: String) in
            s?.write(string: text)
        }
        s.onData = { [weak s]  (data: Data) in
            s?.write(data: data)
        }
        var once = false
        s.onDisconnect = {[weak self, weak s] (error: Error?) in
            if !once {
                once = true
                print("case:\(caseNum) finished")
                //self?.verifyTest(caseNum) //disabled since it slows down the tests
                let nextCase = caseNum+1
                if nextCase <= (self?.caseCount)! {
                    self?.runTest(nextCase)
                    //self?.getTestInfo(nextCase) //disabled since it slows down the tests
                } else {
                    self?.finishReports()
                }
                self?.removeSocket(s)
            }
        }
        s.connect()
    }
    
    func verifyTest(_ caseNum: Int) {
        let s = createSocket("getCaseStatus",caseNum)
        self.socketArray.append(s)
        s.onText = { (text: String) in
            let data = text.data(using: String.Encoding.utf8)
            do {
                let resp: Any? = try JSONSerialization.jsonObject(with: data!,
                    options: JSONSerialization.ReadingOptions())
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
        s.onDisconnect = { [weak self, weak s]  (error: Error?) in
            if !once {
                once = true
                let nextCase = caseNum+1
                print("next test is: \(nextCase)")
                if nextCase <= (self?.caseCount)! {
                    self?.getTestInfo(nextCase)
                } else {
                    self?.finishReports()
                }
            }
            self?.removeSocket(s)
        }
        s.connect()
    }
    
    func finishReports() {
        let s = createSocket("updateReports",0)
        self.socketArray.append(s)
        s.onDisconnect = { [weak self, weak s]  (error: Error?) in
            print("finished all the tests!")
            self?.removeSocket(s)
        }
        s.connect()
    }
    
    func createSocket(_ cmd: String, _ caseNum: Int) -> WebSocket {
        return WebSocket(url: URL(string: "ws://\(host)\(buildPath(cmd,caseNum))")!, protocols: [])
    }
    
    func buildPath(_ cmd: String, _ caseNum: Int) -> String {
        return "/\(cmd)?case=\(caseNum)&agent=Starscream"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

