//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Security.swift
//  Starscream
//
//  Created by Dalton Cherry on 3/16/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation

public enum SecurityErrorCode: UInt16 {
    case acceptFailed = 1
    case pinningFailed = 2
}

// SecurityData is an empty protocol so that an Transport can provide
// the security information needed to do SSL pinning
public protocol SecurityData {
    
}

// the base methods needed to do all the security related things
// e.g. SSL pinning, HTTP response header validation, etc
public protocol Security: class {
    func isValid(data: SecurityData?) -> Bool
    func validate(headers: [String: String], key: String) -> Error?
}
