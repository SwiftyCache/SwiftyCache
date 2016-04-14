//
//  CacheEntrySnapshot.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 21/02/2016.
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

/** 
 A snapshot of the values for a cache entry.
 An entry can have multiple fields. See the 'valueCount' parameter of the method DiskLRUCache.init(cacheDir: String, cacheVersion: Int, valueCount: Int, maxSize: Int64).
 */
public class CacheEntrySnapshot {
    private let key: String
    private let sequenceNumber: Int64
    private let data: [NSData?]
    private let lengths: [Int64]
    
    init(key: String, sequenceNumber: Int64, data: [NSData?], lengths: [Int64]) {
        self.key = key
        self.sequenceNumber = sequenceNumber
        self.data = data
        self.lengths = lengths
    }
    
    
    // MARK: public
    /**
     Returns the value of the field at the specified index.
     
     - parameter index: The field index.
     
     - returns:         The value of the field, which will be nil if the specified field was not read out. See the 'readIndex' parameter of the method DiskLRUCache.getSnapshotForKey(key: String, readIndex: [Bool], ...).
     */
    public func getDataForIndex(index: Int) -> NSData? {
        return data[index]
    }
    
    /**
     Returns the value of the field at the specified index as a UTF-8 encoded string .
     
     - parameter index: The field index.
     
     - returns:         The UTF-8 encoded string value of the field, which will be nil if the specified field was not read out. See the 'readIndex' parameter of the method DiskLRUCache.getSnapshotForKey(key: String, readIndex: [Bool], ...).
     */
    public func getStringDataForIndex(index: Int) -> String? {
        if let strdata = data[index] {
            return String(data: strdata, encoding: NSUTF8StringEncoding)
        } else {
            return nil
        }
    }
    
    /** 
     Returns the byte length of the value of the field at the specified index.
     
     - parameter index: The field index.
     
     - returns:         The byte length of the value.
     */
    public func getLengthForIndex(index: Int) -> Int64 {
        return self.lengths[index]
    }
    
}
