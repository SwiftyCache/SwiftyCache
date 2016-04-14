//
//  LinkedDictionary.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 17/02/2016.
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

class LinkedEntry<Key, Value> {
    
    var key: Key
    var value: Value
    weak var prev: LinkedEntry<Key, Value>!
    weak var next: LinkedEntry<Key, Value>!
    
    init(key: Key, value: Value, prev: LinkedEntry<Key, Value>, next: LinkedEntry<Key, Value>) {
        self.key = key
        self.value = value
        self.prev = prev
        self.next = next
    }
    
    init(dummyKey: Key, dummyValue: Value) {
        self.key = dummyKey
        self.value = dummyValue
        self.prev = self
        self.next = self
    }
    
}

internal struct LinkedDictionaryGenerator<Key, Value> : GeneratorType {
    
    private unowned let dummyHeader: LinkedEntry<Key, Value>
    private unowned var nextResult: LinkedEntry<Key, Value>
    
    init(dummyHeader: LinkedEntry<Key, Value>) {
        self.dummyHeader = dummyHeader
        self.nextResult = dummyHeader.next
    }
    
    mutating func next() -> (Key, Value)? {
        if(self.nextResult === dummyHeader) {
            return nil
        } else {
            let key = self.nextResult.key
            let value = self.nextResult.value
            self.nextResult = self.nextResult.next
            return (key, value)
        }
    }
}


internal class LinkedDictionary<Key: Hashable, Value>: SequenceType {
    typealias LinkedKV = LinkedEntry<Key, Value>
    
    /**
     * A dummy entry in the circular linked list of entries in the map.
     * The first real entry is header.next, and the last is header.prev.
     * If the map is empty, header.next == header && header.prev == header.
     */
    private let header: LinkedKV
    
    
    private var dictionary: [Key: LinkedKV]
    private let accessOrder: Bool
    
    init(dummyKey: Key, dummyValue: Value, initialCapacity: Int, accessOrder: Bool) {
        self.dictionary = Dictionary(minimumCapacity: initialCapacity)
        self.accessOrder = accessOrder
        self.header = LinkedEntry<Key, Value>(dummyKey: dummyKey, dummyValue: dummyValue)
        
    }
    
    func count() -> Int {
        return self.dictionary.count
    }
    
    func get(key: Key) -> Value? {
        if let entry = self.dictionary[key] {
            if self.accessOrder {
                makeTail(entry)
            }
            
            return entry.value
        } else {
            return nil
        }
    }
    
    internal func touchKey(key: Key) -> Bool {
        if let _ = get(key) {
            return true
        } else {
            return false
        }
    }
    
    
    func updateValue(value: Value, forKey key: Key) -> Value? {
        if let v = self.dictionary[key] {
            let oldValue = v.value
            preModify(v)
            v.value = value
            return oldValue
        } else {
            addNewEntry(key, value: value)
            return nil
        }
    }
    
    
    func voidUpdateValue(value: Value, forKey key: Key) {
        if let v = self.dictionary[key] {
            preModify(v)
            v.value = value
        } else {
            addNewEntry(key, value: value)
        }
    }
    
    func removeEldestEntry() -> (Key, Value)? {
        let entry = self.header.next
        if entry === self.header {
            return nil
        } else {
            self.removeValueForKey(entry.key)
            //assert(v! === entry.value)
            return (entry.key, entry.value)
        }
    }
    
    func getEldestEntry() -> (Key, Value)? {
        let entry = self.header.next
        if entry === self.header {
            return nil
        } else {
            //assert(v! === entry.value)
            return (entry.key, entry.value)
        }
    }
    
    func removeValueForKey(key: Key) -> Value? {
        if let v = self.dictionary.removeValueForKey(key) {
            self.postRemove(v)
            return v.value
        } else {
            return nil
        }
    }
    
    func removeAll() {
        self.header.next = self.header
        self.header.prev = self.header
        
        self.dictionary.removeAll()
    }
    
    private func addNewEntry(key: Key, value: Value) {
        // Create new entry, link it on to list, and put it into table
        let oldTail = self.header.prev
        let newTail = LinkedKV(key: key, value: value, prev: oldTail, next: self.header)
        
        oldTail.next = newTail
        self.header.prev = newTail
        self.dictionary[key] = newTail
    }
    
    private func makeTail(e: LinkedKV) {
        // Unlink e
        e.prev.next = e.next
        e.next.prev = e.prev
        
        // Relink e as tail
        let oldTail = self.header.prev
        e.next = self.header
        e.prev = oldTail;
        oldTail.next = e
        self.header.prev = e
    }
    
    private func preModify(e: LinkedKV) {
        if (accessOrder) {
            makeTail(e);
        }
    }
    
    private func postRemove(e: LinkedKV) {
        e.prev.next = e.next
        e.next.prev = e.prev
        e.next = nil
        e.prev = nil
    }
    
    internal func generate() -> LinkedDictionaryGenerator<Key, Value> {
        return LinkedDictionaryGenerator(dummyHeader: self.header)
    }
}
