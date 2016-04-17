//: A Playground for SwiftyCache on iOS

import XCPlayground
import SwiftyCache

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true


let cacheDir = XCPlaygroundSharedDataDirectoryURL.URLByAppendingPathComponent("iOSTestCache", isDirectory: true).path!

let valueCount = 2 // each entry has two fields
let diskCache = DiskLRUCache(cacheDir: cacheDir, cacheVersion: 1, valueCount: valueCount, maxSize: 1024*1024*2)

let value0 = "Hello, world!".dataUsingEncoding(NSUTF8StringEncoding)!
let value1 = "Hello, SwiftyCache!".dataUsingEncoding(NSUTF16StringEncoding)!

let key = "Hello"
diskCache.setData([value0, value1], forKey: key)

diskCache.getSnapshotForKey(key) { (error: NSError?, snapshot: CacheEntrySnapshot?) in

    if let snapshot = snapshot {
        NSLog(snapshot.getStringDataAtIndex(0, encoding: NSUTF8StringEncoding)!)
        NSLog(snapshot.getStringDataAtIndex(1, encoding: NSUTF16StringEncoding)!)
        XCPlaygroundPage.currentPage.finishExecution()
    } else {
        print("We didn't get the snapshot. Error: \(error)")
        XCPlaygroundPage.currentPage.finishExecution()
    }
}
