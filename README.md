SwiftyCache
==============
<p align="center">

<a href="https://travis-ci.org/SwiftyCache/SwiftyCache"><img src="https://img.shields.io/travis/SwiftyCache/SwiftyCache/master.svg"></a>

<a href="https://github.com/Carthage/Carthage/"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>

<a href="http://cocoadocs.org/docsets/SwiftyCache"><img src="https://img.shields.io/cocoapods/v/SwiftyCache.svg?style=flat"></a>

<a href="http://cocoadocs.org/docsets/SwiftyCache"><img src="https://img.shields.io/cocoapods/p/SwiftyCache.svg?style=flat"></a>

<img src="https://img.shields.io/badge/Swift-2.2-orange.svg">

</p>

SwiftyCache is a journal-based disk LRU cache library that reimplements the Java
library [DiskLruCache](https://github.com/JakeWharton/DiskLruCache) in Swift 2.2.

## A Brief History of DiskLruCache
[DiskLruCache](https://github.com/JakeWharton/DiskLruCache) was originally from the
Android Open Source Project, and it has been maintained on GitHub by [Jake Wharton](https://github.com/JakeWharton) and other contributors. [A modified version](https://github.com/square/okhttp/blob/master/okhttp/src/main/java/okhttp3/internal/DiskLruCache.java)
has been integrated into [OkHttp](http://square.github.io/okhttp/) by Square. Since
OkHttp has been the built-in HTTP client that powers HttpUrlConnection [since Android
 4.4](https://packetzoom.com/blog/which-android-http-library-to-use.html), all of
the modern Android devices have a version of DiskLruCache installed inside.

## Features

The following description comes from [DiskLruCache](https://github.com/JakeWharton/DiskLruCache),
modified accordingly.

SwiftyCache is a cache that uses a bounded amount of space on a filesystem based
on the LRU strategy. Each cache entry has a string key and a fixed number of values.
Each key must match the regex `[a-z0-9_-]{1,120}`. Values are byte sequences,
accessible as NSData objects or strings. The size in bytes of each value must be
between 0 and the maxinum size an NSData object can hold.

The cache stores its data in a directory on the filesystem. This directory must
be exclusive to the cache; the cache may delete or overwrite files from its
directory. It is an error for multiple processes to use the same cache
directory at the same time.

This cache limits the number of bytes that it will store on the filesystem. When
the number of stored bytes exceeds the limit, the cache will remove the least recently
used entries in the background until the limit is satisfied. The limit is not
strict: the cache may temporarily exceed it while waiting for files to be
deleted. The limit does not include filesystem overhead or the cache journal so
space-sensitive applications should set a conservative limit.

Clients call `setData` to create or update the values of an entry, or `setPartialData`
to update part of the values of an existing entry.

 *  When an entry is being **created/updated** by `setData` it is necessary to
 supply a full set of values; the empty value should be used as a placeholder
 if necessary.
 *  When an entry is being **partially updated** by `setPartialData`, it is not
 necessary to supply data for every value; values default to their previous value.

Clients call `getSnapshotForKey` to read a snapshot of an entry. The read will 
observe the value at the time that the reading operation is performed in the
background dispatch queue. Updates and removals after the operation do not impact
the values in the snapshot.

## Usage

```swift

let cachesDirURL = NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask)[0]
let cacheDir = cachesDirURL.URLByAppendingPathComponent("TestCache", isDirectory: true).path!
        
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
    }
}

```

## Installation

### CocoaPods

You can use [CocoaPods](http://cocoapods.org/) to install `SwiftyCache`by adding it
to your `Podfile`:

```ruby
platform :ios, '8.0'
use_frameworks!

target 'MyApp' do
	pod 'SwiftyCache', '~> 0.9'
end
```

### Carthage


Please install Carthage if it is not available on your Mac. Visit [https://github.com/Carthage/Carthage](https://github.com/Carthage/Carthage) for details.

Add the following line in your `Cartfile`:

``` ogdl
github "SwiftyCache/SwiftyCache" ~> 0.9
```

And run the following command to build SwiftyCache:

``` bash
$ carthage update

```

Then integrate the framework into your Xcode project manually following the steps [here](https://github.com/Carthage/Carthage/#getting-started).


## License

    Copyright 2016 SwiftyCache

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
