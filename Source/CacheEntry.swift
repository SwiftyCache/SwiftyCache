//
//  CacheEntry.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 18/02/2016.
//
//  Copyright (C) 2016 SwiftyCache
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

class CacheEntry {
    let key: String
    
    /** Lengths of this entry's files. */
    var lengths: [Int64]
    
    /** True if this entry has ever been published. */
    var readable: Bool = false
    
    /** The ongoing edit or null if this entry is not being edited. */
    var currentEditor: CacheEntryEditor?
    
    /** The sequence number of the most recently committed edit to this entry. */
    var sequenceNumber: Int64 = 0
    
    init(key: String, valueCount: Int) {
        self.key = key
        self.lengths = [Int64](count: valueCount, repeatedValue: 0)
    }
    
    func setLengths(lens: [Int64]) {
        self.lengths = lens
    }
    
    internal func getLengths() -> String {
        return self.lengths.map({"\($0)"}).joinWithSeparator(" ")
    }
        
    static func dummyValue() -> CacheEntry {
        return CacheEntry(key: "dummy", valueCount: 1);
    }
}
