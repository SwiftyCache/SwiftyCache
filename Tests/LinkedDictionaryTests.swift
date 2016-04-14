//
//  LinkedDictionaryTests.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 22/03/2016.
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

import XCTest
@testable import SwiftyCache

class Counter {
    var value: Int = 0
    
    func increment() {
        self.value += 1
    }
    
    func decrement() {
        self.value -= 1
    }
}

class Str {
    var str: String
    var counter: Counter
    init(str: String, counter: Counter) {
        self.str = str
        self.counter = counter
        
        self.counter.increment()
    }
    deinit {
        print("Str deinit: \(str)")
        self.counter.decrement()
    }
}

func printDic(dic: LinkedDictionary<Int, Str>) {
    for (key, value) in dic {
        print("key: \(key), value: \(value.str)")
    }
}


class LinkedDictionaryTests: XCTestCase {

    private var dic: LinkedDictionary<Int, Str>!
    private var counter: Counter!
    
    override func setUp() {
        super.setUp()
        
        self.counter = Counter()
        self.dic = LinkedDictionary<Int, Str>(dummyKey: 0, dummyValue: Str(str: "dummy", counter: self.counter), initialCapacity: 10, accessOrder: true)
    }
    
    func deinitDic() {
        self.dic = nil
    }
    
    override func tearDown() {
        self.deinitDic()
        XCTAssertTrue(self.counter.value == 0)
        super.tearDown()
    }

    func testLinkedDic() {
        dic.updateValue(Str(str: "1", counter: self.counter), forKey: 1)
        var old1 = dic.updateValue(Str(str: "new1", counter: self.counter), forKey: 1)
        XCTAssertEqual("1", old1!.str)
        
        old1 = nil
        print("--Str deinit: 1 here")
        
        dic.updateValue(Str(str: "2", counter: self.counter), forKey: 2)
        dic.updateValue(Str(str: "3", counter: self.counter), forKey: 3)
        dic.voidUpdateValue(Str(str: "new3", counter: self.counter), forKey: 3)
        print("--here comes Str deinit: 3")
        
        dic.updateValue(Str(str: "new2", counter: self.counter), forKey: 2)
        print("anonymous ref to key 2")
        print("--no Str deinit: 2 here")
        
        //print("touch key 2")
        var two: Str? // = dic.get(2)
        
        
        XCTAssertEqual(3, dic.count())
        
        
        printDic(dic)
        
        two = dic.removeValueForKey(2)
        XCTAssertEqual(2, dic.count())
        print("key 2 removed: \(two!.str)")
        two = nil
        print("--Str deinit: new2 should be here, but not, why???")
        
        
        printDic(dic)
        
        dic.touchKey(1)
        print("touch key 1")
        printDic(dic)
        
        dic.touchKey(3)
        print("touch key 3")
        printDic(dic)
        
        let (key1, entry1) = dic.getEldestEntry()!
        XCTAssertEqual(1, key1)
        
        let (keyOne, entryOne) = dic.removeEldestEntry()!
        print("removeEldestEntry key 1")
        XCTAssertEqual(1, keyOne)
        XCTAssertTrue(entry1 === entryOne)
        
        XCTAssertEqual(1, dic.count())
        XCTAssertEqual("new3", dic.get(3)!.str)
        printDic(dic)
        
        
        dic.removeAll()
        print("after dic.removeAll()")
        
        
        print("test method exits")
        
    }

}
