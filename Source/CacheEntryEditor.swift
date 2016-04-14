//
//  CacheEntryEditor.swift
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

class CacheEntryEditor {
    private unowned let lruCache: DiskLRUCache
    unowned let entry: CacheEntry
    var written: [Bool]?
    private var hasErrors: Bool = false

    init(lruCache: DiskLRUCache, entry: CacheEntry) {
        self.lruCache = lruCache
        self.entry = entry
        if (entry.readable) {
            self.written = nil
        } else {
            self.written = [Bool](count: lruCache.valueCount, repeatedValue: false);
        }
    }
    
    func setValue(value: NSData, forIndex index: Int) -> Bool {
        if (!self.entry.readable) {
            self.written![index] = true
        }
        
        let path = self.lruCache.getDirtyFilePathForKey(self.entry.key, index: index)
        if value.writeToFile(path, atomically: false) {
            return true
        } else {
            self.hasErrors = true
            return false
        }
    }
    
    func syncCommit() throws {
        if (hasErrors) {
            let key = self.entry.key // the next line can remove the entry in the cache, so we get the key first before self.entry becomes a dangling pointer.
            try lruCache.completeEdit(self, success: false)
            try lruCache.syncRemoveEntryForKey(key) // The previous entry is stale.
        } else {
            try lruCache.completeEdit(self, success: true)
        }
    }

    func syncAbort() throws {
        try lruCache.completeEdit(self, success: false)
    }

}
