//
//  DiskLRUCacheTests.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 1/03/2016.
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

private let MAGIC = "io.github.swiftycache.DiskLRUCache"
private let VERSION_1 = "1"
private let VALUE_COUNT = 2
private let CACHE_VERSION = 100

private let WAIT_TIME: NSTimeInterval = 3.0

class DiskLRUCacheTests: XCTestCase {
    
    private var cacheDir: String!
    private var journalFile: String!
    private var journalBkpFile: String!
    private var cache: DiskLRUCache!
    
    override func setUp() {
        super.setUp()
        
        let tmp = NSTemporaryDirectory() as NSString
        self.cacheDir = tmp.stringByAppendingPathComponent("DiskLRUCacheTest")
        
        print("cacheDir: \(cacheDir)")
        
        let fileManager = NSFileManager.defaultManager()
        
        var isDir = ObjCBool(false)
        if fileManager.fileExistsAtPath(self.cacheDir, isDirectory: &isDir) && isDir {
            
            let enumerator = fileManager.enumeratorAtPath(self.cacheDir)!
            
            while let fileName = enumerator.nextObject() as? String {
                try! fileManager.removeItemAtPath((self.cacheDir as NSString).stringByAppendingPathComponent(fileName))
            }
        }
        
        self.journalFile = (self.cacheDir as NSString).stringByAppendingPathComponent("journal")
        self.journalBkpFile = (self.cacheDir as NSString).stringByAppendingPathComponent("journal.bkp")
        
        self.cache = newDiskLRUCacheInstance()
    }
    
    func newDiskLRUCacheInstance(maxSize maxSize: Int64 = INT64_MAX) -> DiskLRUCache {
        return DiskLRUCache(cacheDir: cacheDir, cacheVersion: CACHE_VERSION, valueCount: VALUE_COUNT, maxSize: maxSize)
    }

    func newDiskLRUCacheInstance(redundantOpThreshold redundantOpThreshold: Int) -> DiskLRUCache {
        let cache = DiskLRUCache(cacheDir: cacheDir, cacheVersion: CACHE_VERSION, valueCount: VALUE_COUNT, maxSize: INT64_MAX)
        cache.setRedundantOpCompactThreshold(redundantOpThreshold)
        return cache
    }
    
    override func tearDown() {
        try! self.cache.closeNow()
        self.cache = nil
        super.tearDown()
    }
    
    func readJournalLines() -> [String] {
        
        let journalContents = try! String(contentsOfFile: self.journalFile, encoding: NSUTF8StringEncoding)
        return journalContents.characters.split(allowEmptySlices: true){$0 == "\n"}.map(String.init)
    }
    
    func assertJournalBodyEquals(lines: String...) {
        
        var expectedLines = [String]()
        expectedLines.append(MAGIC)
        expectedLines.append(VERSION_1)
        expectedLines.append("\(CACHE_VERSION)")
        expectedLines.append("\(VALUE_COUNT)")
        expectedLines.append("")
        expectedLines.appendContentsOf(lines)
        expectedLines.append("")
        
        XCTAssertEqual(readJournalLines(), expectedLines)
    }
    
    func writeFile(path: String, content: String) {
        try! content.writeToFile(path, atomically: true, encoding: NSUTF8StringEncoding)
    }
    
    func getJournalHeader(magic magic: String = MAGIC, version: String = VERSION_1,
        cacheVersion: Int = CACHE_VERSION, valueCount: Int = VALUE_COUNT, blankLine: String = "") -> String {
        return magic + "\n" + version + "\n" + "\(cacheVersion)" + "\n" + "\(valueCount)" + "\n" + blankLine + "\n"
    }
    
    func createJournalWithHeader(header: String, bodyLines: String...) {
        var content = header
        bodyLines.forEach { (line: String) -> () in
            content = content + line + "\n"
        }
        
        writeFile(self.journalFile, content: content)
    }
    
    func createJournalWithHeader(header: String, body: String) {
        writeFile(self.journalFile, content: header + body)
    }
    
    func createJournalWithBody(body: String) {
       createJournalWithHeader(getJournalHeader(), body: body)
    }
    
    func getCleanFilePathForKey(key: String, index: Int) -> String {
        return self.cacheDir + "/" + key + ".\(index)"
    }
    
    func getDirtyFilePathForKey(key: String, index: Int) -> String {
        return self.cacheDir + "/" + key + ".\(index).tmp"
    }
    
    func testEmptyCache() {
        try! cache.closeNow();
        assertJournalBodyEquals()
    }
    
    func strToNSData(str: String) -> NSData {
        return str.dataUsingEncoding(NSUTF8StringEncoding)!
    }
    
    func assertFileNotExists(path: String) {
        let fileManager = NSFileManager.defaultManager()
        XCTAssertFalse(fileManager.fileExistsAtPath(path), "should not exist: \(path)")
    }
    
    func assertFileExists(path: String) {
        let fileManager = NSFileManager.defaultManager()
        XCTAssertTrue(fileManager.fileExistsAtPath(path), "should exist: \(path)")
    }
    
    func assertFileAtPath(path: String, content: String) {
        assertFileExists(path)
        let str = try! String(contentsOfFile: path, encoding: NSUTF8StringEncoding)
        XCTAssertEqual(content, str)
    }
    
    func assertCacheFilesNotExistForKey(key: String) {
        assertFileNotExists(self.cacheDir + "/" + key + ".0")
        assertFileNotExists(self.cacheDir + "/" + key + ".1")
    }
    
    func assertCacheEntryForKey(key: String, index: Int, value: String) {
        let path = self.cacheDir + "/" + key + ".\(index)"
        assertFileExists(path)
        assertFileAtPath(path, content: value)
    }
    
    func assertInvalidKey(invalidKey: String) {
        XCTAssertFalse(self.cache.isValidKey(invalidKey))
        
        let data1 = strToNSData("f1")
        
        let expectation = self.expectationWithDescription("Caught invalid key: \(invalidKey)")
        
        
        self.cache.setData([data1, data1], forKey: invalidKey) { (error: NSError?) in
            guard let error = error else {
                XCTFail("should not be here, '\(invalidKey)' should be an invalid key")
                return
            }
            XCTAssertEqual(error.localizedDescription, "Invalid key: \(invalidKey)")
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func assertValidKey(key: String) {
        XCTAssertTrue(self.cache.isValidKey(key), "'\(key)' should be a valid key.")
    }
    
    func assertSuccessOnRemoveEntryForKey(key: String, isRemoved: Bool = true) {
        let expectation = self.expectationWithDescription("entry removed for key: \(key)")
        
        self.cache.removeEntryForKey(key) { (error: NSError?, removed: Bool) in

            XCTAssertNil(error, "should not be here, error happened when removing entry for key: \(key)")
            
            XCTAssertEqual(removed, isRemoved)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func testValidateKey() {
        assertInvalidKey("invalid/key")
        
        assertInvalidKey("invalid key")
        assertInvalidKey("invalid\tkey")
        assertInvalidKey("invalid\nkey")
        assertInvalidKey("invalid\rkey")
        assertInvalidKey("invalid\r\nkey")
        assertInvalidKey("`")
        
        assertValidKey("-")
        assertValidKey("___-")
        assertValidKey("A")
        assertValidKey("ABCD")
        assertValidKey("aaAA")
        assertValidKey("a")
        assertValidKey("abcd")
        assertValidKey("1")
        assertValidKey("1234")
        assertValidKey("Aa1Bb2Cc3-Dd4_0")
        assertInvalidKey("人")
        assertInvalidKey("©")
        let str120chars = "123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_123456789_"
        assertValidKey(str120chars)
        assertInvalidKey(str120chars + "a")
        assertInvalidKey("😄😄😄")
        assertInvalidKey("😄😄")
        assertInvalidKey("😄")
        
        assertInvalidKey("")
        assertInvalidKey(" ")
        assertInvalidKey("\n")
        assertInvalidKey("\r\n")
        assertInvalidKey("\t")
        assertInvalidKey("      ")
    }
    
    func assertNilSnapshotForKey(key: String) {
        let expectation = self.expectationWithDescription("getSnapshotForKey: \(key) returned nil as expected")
        
        self.cache.getSnapshotForKey(key, readIndex: [true, true]) { (error: NSError?, snapshot:CacheEntrySnapshot?) in

            XCTAssertNil(error, "should not be here, failed to getSnapshotForKey: \(key). Error: \(error)")
            
            XCTAssertNil(snapshot)
            expectation.fulfill()
        }
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func assertSuccessOnSetDataForKey(key: String, value0: String, value1: String) {
        assertSuccessOnSetDataForKey(key, value0: value0, value1: value1, cache: self.cache)
    }
    
    func assertSuccessOnSetDataForKey(key: String, value0: String, value1: String, cache diskCache: DiskLRUCache) {
        let expectationSetData = self.expectationWithDescription("setData:forKey \(key) succeeded as expected")
        
        diskCache.setData([strToNSData(value0), strToNSData(value1)], forKey: key) { (error: NSError?) in
            XCTAssertNil(error, "should not be here, failed to setData:forKey \(key), error: \(error)")
            expectationSetData.fulfill()
        }
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func assertErrorOnSetDataForKey(key: String, value0: String, value1: String) {
        assertErrorOnSetDataForKey(key, value0: value0, value1: value1, cache: self.cache)
    }
    
    func assertErrorOnSetDataForKey(key: String, value0: String, value1: String, cache diskCache: DiskLRUCache) {
        let expectation = self.expectationWithDescription("setData:forKey \(key) had error as expected")
        
        diskCache.setData([strToNSData(value0), strToNSData(value1)], forKey: key) { (error: NSError?) in
            XCTAssertNotNil(error)
            XCTAssertEqual(error!.localizedDescription, "Failed to set value for key:\(key) index:0")
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }

    func assertSuccessOnSetPartialDataForKey(key: String, value: String, index: Int, cache diskCache: DiskLRUCache) {
        let expectationSetData = self.expectationWithDescription("setPartialData:forExistingKey \(key) succeeded as expected")
        
        diskCache.setPartialData([(strToNSData(value), index)], forExistingKey: key) { (error: NSError?) in
            XCTAssertNil(error, "should not be here, failed to setPartialData:forExistingKey \(key)")
            expectationSetData.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func assertErrorOnSetPartialDataForKey(key: String, value: String, index: Int, cache diskCache: DiskLRUCache) {
        let expectation = self.expectationWithDescription("setPartialData:forExistingKey \(key) had error as expected")
        
        diskCache.setPartialData([(strToNSData(value), index)], forExistingKey: key) { (error: NSError?) in
            XCTAssertNotNil(error)
            XCTAssertEqual(error!.localizedDescription, "Failed to set partial data for key:\(key) index:\(index)")
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }

    
    func assertEmptyDir(path: String) {
        let fileManager = NSFileManager.defaultManager()
        let enumerator = fileManager.enumeratorAtPath(path)!

        while let fileName = enumerator.nextObject() as? String {
            XCTFail("\(path) should be empty, but file exits at \(fileName)")
        }
    }
    
    func assertSuccessOnDeleteCache() {
        let expectation = self.expectationWithDescription("cache deleted as expected")
        
        self.cache.delete { (error: NSError?) in
            XCTAssertNil(error, "should not be here, failed to delete the cache")
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
        
        assertFileNotExists(self.cacheDir)
        XCTAssertTrue(self.cache.isClosed())
    }
    
    func assertErrorOnSetPartialDataForNewKey(key: String, value: String, index: Int, cache diskCache: DiskLRUCache) {
        let expectation = self.expectationWithDescription("setPartialData:forExistingKey \(key) had error as expected")
        
        diskCache.setPartialData([(strToNSData(value), index)], forExistingKey: key) { (error: NSError?) in
            
            var indexWithoutValue = 0
            if index == 0 {
                indexWithoutValue = 1
            }
            XCTAssertNotNil(error)
            XCTAssertEqual(error!.localizedDescription, "Newly created entry didn't create value for index: \(indexWithoutValue)")
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
    }
    
    func assertOnGetSnapshotForKey(key: String, value0: String, value1: String, cache diskCache: DiskLRUCache) -> CacheEntrySnapshot? {
        let expectationGetData = self.expectationWithDescription("getSnapshotForKey: \(key) returned the data as expected")
        
        var ss: CacheEntrySnapshot? = nil
        
        diskCache.getSnapshotForKey(key, readIndex: [true, true]) { (error: NSError?, snapshot: CacheEntrySnapshot?) in
            XCTAssertNil(error)
            
            ss = snapshot
            XCTAssertNotNil(snapshot)
            XCTAssertEqual(snapshot!.getDataAtIndex(0), self.strToNSData(value0))
            XCTAssertEqual(snapshot!.getDataAtIndex(1), self.strToNSData(value1))
            XCTAssertEqual(snapshot!.getStringDataAtIndex(0, encoding: NSUTF8StringEncoding), value0)
            XCTAssertEqual(snapshot!.getStringDataAtIndex(1, encoding: NSUTF8StringEncoding), value1)
            
            expectationGetData.fulfill()
        }
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
        return ss
    }
    
    func assertOnGetSnapshotForKey(key: String, value0: String, value1: String) -> CacheEntrySnapshot? {
        return assertOnGetSnapshotForKey(key, value0: value0, value1: value1, cache: self.cache)
    }
    
    func assertSuccessOnCloseCache(diskCache: DiskLRUCache) {
        XCTAssertFalse(diskCache.isClosed())
        let expectationClose = self.expectationWithDescription("cache closed")
        
        diskCache.close { (error: NSError?) in
            XCTAssertNil(error)
            expectationClose.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(WAIT_TIME, handler: nil)
        
        XCTAssertTrue(diskCache.isClosed())
    }
    
    func testWriteAndReadEntry() {
        let key1 = "key1"
        let abc = "abc"
        let de = "de"
        
        assertNilSnapshotForKey(key1)
        
        assertSuccessOnSetDataForKey(key1, value0: abc, value1: de)
        
        assertOnGetSnapshotForKey(key1, value0: abc, value1: de)
        
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2", "READ key1")
    }
    
    
    func testReadAndWriteEntryAcrossCacheOpenAndClose() {
        let key1 = "key1"
        let abc = "abc"
        let de = "de"
        
        assertNilSnapshotForKey(key1)
        
        assertSuccessOnSetDataForKey(key1, value0: abc, value1: de)
        
        assertSuccessOnCloseCache(self.cache)

        self.cache = newDiskLRUCacheInstance()
        
        assertOnGetSnapshotForKey(key1, value0: abc, value1: de)
        
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2", "READ key1")
    }
    
    func testReadAndWriteEntryWithoutProperClose() {
        let key1 = "key1"
        let abc = "abc"
        let de = "de"
        assertSuccessOnSetDataForKey(key1, value0: abc, value1: de)
        
        // Simulate a dirty close of 'cache' (e.g. it is not close properly) by opening the cache directory again.
        let cache2 = newDiskLRUCacheInstance()
        assertOnGetSnapshotForKey(key1, value0: abc, value1: de, cache: cache2)
        assertSuccessOnSetDataForKey(key1, value0: abc, value1: "defg", cache: cache2)
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2", "READ key1", "DIRTY key1", "CLEAN key1 3 4")
        
        assertSuccessOnCloseCache(cache2)
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2", "READ key1", "DIRTY key1", "CLEAN key1 3 4")
    }
    
    func testJournalWithEditAndPublish() {
        assertSuccessOnSetDataForKey("key1", value0: "abc", value1: "de")
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2")
        
        assertSuccessOnCloseCache(self.cache)
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2")
    }
    
    func testPartiallySetNewKeyIsRemoveInJournal() {
        assertErrorOnSetPartialDataForNewKey("key1", value: "abc", index: 0, cache: self.cache)
        assertJournalBodyEquals("DIRTY key1", "REMOVE key1")
        assertCacheFilesNotExistForKey("key1")
    }
    
    func testSetPartialDataForKey() {
        assertSuccessOnSetDataForKey("key1", value0: "abc", value1: "de")
        assertSuccessOnSetPartialDataForKey("key1", value: "fghi", index: 1, cache: self.cache)
        
        assertJournalBodyEquals("DIRTY key1", "CLEAN key1 3 2", "DIRTY key1", "CLEAN key1 3 4")
        
        assertSuccessOnCloseCache(self.cache)
        
        self.cache = newDiskLRUCacheInstance()
        assertOnGetSnapshotForKey("key1", value0: "abc", value1: "fghi")
    }
    
    func testJournalWithEditAndPublishAndRead() {
        assertSuccessOnSetDataForKey("k1", value0: "AB", value1: "C")
        assertSuccessOnSetDataForKey("k2", value0: "DEF", value1: "G")
        assertOnGetSnapshotForKey("k1", value0: "AB", value1: "C")
        assertJournalBodyEquals("DIRTY k1", "CLEAN k1 2 1", "DIRTY k2", "CLEAN k2 3 1", "READ k1")
    }
    
    func testExplicitRemoveAppliedToDiskImmediately() {
        assertSuccessOnSetDataForKey("k1", value0: "AB", value1: "C")
        assertCacheEntryForKey("k1", index: 0, value: "AB")
        assertCacheEntryForKey("k1", index: 1, value: "C")
        assertSuccessOnRemoveEntryForKey("k1")
        assertCacheFilesNotExistForKey("k1")
    }
    
    func testOpenWithDirtyKeyDeletesAllFilesForThatKey() {
        assertSuccessOnCloseCache(self.cache)
        let cleanFile0 = getCleanFilePathForKey("k1", index: 0)
        let cleanFile1 = getCleanFilePathForKey("k1", index: 1)
        let dirtyFile0 = getDirtyFilePathForKey("k1", index: 0)
        let dirtyFile1 = getDirtyFilePathForKey("k1", index: 1)
        writeFile(cleanFile0, content: "A")
        writeFile(cleanFile1, content: "B")
        writeFile(dirtyFile0, content: "C")
        writeFile(dirtyFile1, content: "D");
        createJournalWithBody("CLEAN k1 1 1\nDIRTY k1\n")
        
        self.cache = newDiskLRUCacheInstance()
        
        assertNilSnapshotForKey("k1")
        
        assertFileNotExists(cleanFile0)
        assertFileNotExists(cleanFile1)
        assertFileNotExists(dirtyFile0)
        assertFileNotExists(dirtyFile1)
    }
    
    func assertValidJournalLine(line: String, key: String, value0: String, value1: String) {
        assertSuccessOnCloseCache(self.cache)
        let cleanFile0 = getCleanFilePathForKey(key, index: 0)
        let cleanFile1 = getCleanFilePathForKey(key, index: 1)
        let dirtyFile0 = getDirtyFilePathForKey(key, index: 0)
        let dirtyFile1 = getDirtyFilePathForKey(key, index: 1)
        writeFile(cleanFile0, content: value0)
        writeFile(cleanFile1, content: value1)
        
        createJournalWithBody(line + "\n")
        
        self.cache = newDiskLRUCacheInstance()
        assertOnGetSnapshotForKey(key, value0: value0, value1: value1)

        assertFileExists(cleanFile0)
        assertFileExists(cleanFile1)
        assertFileNotExists(dirtyFile0)
        assertFileNotExists(dirtyFile1)
    }
    
    
    
    func assertMalformedJournalLine(line: String, key: String, value0: String, value1: String) {
        assertSuccessOnCloseCache(self.cache)
        
        generateSomeGarbageFiles()
        
        let cleanFile0 = getCleanFilePathForKey(key, index: 0)
        let cleanFile1 = getCleanFilePathForKey(key, index: 1)
        let dirtyFile0 = getDirtyFilePathForKey(key, index: 0)
        let dirtyFile1 = getDirtyFilePathForKey(key, index: 1)
        writeFile(cleanFile0, content: value0)
        writeFile(cleanFile1, content: value1)
        
        createJournalWithBody(line + "\n")
        self.cache = newDiskLRUCacheInstance()
        assertNilSnapshotForKey(key)
        
        assertFileNotExists(cleanFile0)
        assertFileNotExists(cleanFile1)
        assertFileNotExists(dirtyFile0)
        assertFileNotExists(dirtyFile1)
        
        assertGarbageFilesAllDeleted()
    }
    
    func testJournalLines() {
        assertValidJournalLine("CLEAN k1 1 1", key: "k1", value0: "A", value1: "B")
        assertValidJournalLine("CLEAN k1 0 2", key: "k1", value0: "", value1: "Bc")

        // wrong value size, but still valid!!
        assertValidJournalLine("CLEAN k1 1 2", key: "k1", value0: "A", value1: "B")
        
        // two spaces instead of one behind CLEAN
        assertMalformedJournalLine("CLEAN  k1 1 1", key: "k1", value0: "A", value1: "B")

        // wrong value count
        assertMalformedJournalLine("CLEAN k1 1 2 3", key: "k1", value0: "A", value1: "B")
        
        // malformed number
        assertMalformedJournalLine("CLEAN k1 1k 1", key: "k1", value0: "A", value1: "B")

        // invalid status
        assertMalformedJournalLine("BADStatus k1 1 1", key: "k1", value0: "A", value1: "B")
        
        // invalid line
        assertMalformedJournalLine("CLEAN k1 1 1\nBOGUS", key: "k1", value0: "A", value1: "B")    }
    
    func generateSomeGarbageFiles() {
        let fileManager = NSFileManager.defaultManager()
        let dir1 = self.cacheDir + "/dir1"
        try! fileManager.createDirectoryAtPath(dir1, withIntermediateDirectories: false, attributes: nil)
        
        let dir2 = self.cacheDir + "/dir2"
        try! fileManager.createDirectoryAtPath(dir2, withIntermediateDirectories: false, attributes: nil)
        
        let fileUnderDir2 = dir2 + "/otherFile1"
        writeFile(fileUnderDir2, content: "F")
        
        let cleanG1File0 = getCleanFilePathForKey("g1", index: 0)
        writeFile(cleanG1File0, content: "A")

        let cleanG1File1 = getCleanFilePathForKey("g1", index: 1)
        writeFile(cleanG1File1, content: "B")
        
        let cleanG2File0 = getCleanFilePathForKey("g2", index: 0)
        writeFile(cleanG2File0, content: "C")

        let cleanG2File1 = getCleanFilePathForKey("g2", index: 1)
        writeFile(cleanG2File1, content: "D")
    }
    
    func assertGarbageFilesAllDeleted() {
        let dir1 = self.cacheDir + "/dir1"
        assertFileNotExists(dir1)
        
        let dir2 = self.cacheDir + "/dir2"
        assertFileNotExists(dir2)
        
        let fileUnderDir2 = dir2 + "/otherFile1"
        assertFileNotExists(fileUnderDir2)
        
        assertFileNotExists(getCleanFilePathForKey("g1", index: 0))
        assertFileNotExists(getCleanFilePathForKey("g1", index: 1))
        assertFileNotExists(getCleanFilePathForKey("g2", index: 0))
        assertFileNotExists(getCleanFilePathForKey("g2", index: 1))
    }
    
    func testEmptyJournalBody() {
        assertSuccessOnCloseCache(self.cache)
        
        let header = getJournalHeader()
        createJournalWithHeader(header, body: "")
        
        self.cache = newDiskLRUCacheInstance()
        assertNilSnapshotForKey("NoSuchKey")
        XCTAssertEqual(0, self.cache.size)
    }
    
    func assertInvalidJournalHeader(header: String) {
        assertSuccessOnCloseCache(self.cache)
        
        generateSomeGarbageFiles()
        createJournalWithHeader(header)
        
        self.cache = newDiskLRUCacheInstance()
        assertNilSnapshotForKey("NoSuchKey")
        XCTAssertEqual(0, self.cache.size)
        
        assertGarbageFilesAllDeleted()
    }
    
    func testInvalidJournalHeaders() {
        assertInvalidJournalHeader(getJournalHeader(version: "0"))
        assertInvalidJournalHeader(getJournalHeader(cacheVersion: 101))
        assertInvalidJournalHeader(getJournalHeader(valueCount: 1))
        assertInvalidJournalHeader(getJournalHeader(magic: MAGIC + " "))
        assertInvalidJournalHeader(getJournalHeader(blankLine: " "))
    }

    func testOpenWithTruncatedLineWillNotDiscardThatLine() {
        assertSuccessOnCloseCache(self.cache)
        
        let key = "k1"
        let value0 = "A"
        let value1 = "B"
        
        let cleanFile0 = getCleanFilePathForKey(key, index: 0)
        let cleanFile1 = getCleanFilePathForKey(key, index: 1)
        writeFile(cleanFile0, content: value0)
        writeFile(cleanFile1, content: value1)
        
        createJournalWithBody("CLEAN k1 1 1") // no trailing newline
        assertFileAtPath(journalFile, content: getJournalHeader() + "CLEAN k1 1 1")
        self.cache = newDiskLRUCacheInstance()
        
        assertOnGetSnapshotForKey(key, value0: value0, value1: value1)
        
        assertSuccessOnCloseCache(self.cache)
        
        assertJournalBodyEquals("CLEAN k1 1 1", "READ k1")
        assertFileAtPath(journalFile, content: getJournalHeader() + "CLEAN k1 1 1\nREAD k1\n")
    }
    
    func testEvictOnInsert() {
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "aaa") // size 4
        assertSuccessOnSetDataForKey("b", value0: "bb", value1: "bbbb") // size 6
        XCTAssertEqual(10, self.cache.size)
        
        // Cause the size to grow to 12 should evict 'a'.
        assertSuccessOnSetDataForKey("c", value0: "c", value1: "c")
        //XCTAssertEqual(12, self.cache.getSize()) // it is an async process to evict. The assert may fail sometimes.
        assertNilSnapshotForKey("a")
        XCTAssertEqual(8, self.cache.size)
        assertJournalBodyEquals("DIRTY a", "CLEAN a 1 3", "DIRTY b", "CLEAN b 2 4", "DIRTY c", "CLEAN c 1 1", "REMOVE a")
        
        // Causing the size to grow to 10 should evict nothing.
        assertSuccessOnSetDataForKey("d", value0: "d", value1: "d")
        assertNilSnapshotForKey("a")
        XCTAssertEqual(10, self.cache.size)
        assertOnGetSnapshotForKey("b", value0: "bb", value1: "bbbb")
        assertOnGetSnapshotForKey("c", value0: "c", value1: "c")
        assertOnGetSnapshotForKey("d", value0: "d", value1: "d")
        
        // Causing the size to grow to 18 should evict 'B' and 'C'.
        assertSuccessOnSetDataForKey("e", value0: "eeee", value1: "eeee")
        assertNilSnapshotForKey("a")
        assertNilSnapshotForKey("b")
        assertNilSnapshotForKey("c")
        assertOnGetSnapshotForKey("d", value0: "d", value1: "d")
        assertOnGetSnapshotForKey("e", value0: "eeee", value1: "eeee")
        
    }
    
    func testEvictionHonorsLruFromCurrentSession() {
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
        assertSuccessOnSetDataForKey("c", value0: "c", value1: "c")
        assertSuccessOnSetDataForKey("d", value0: "d", value1: "d")
        assertSuccessOnSetDataForKey("e", value0: "e", value1: "e")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")// 'b' is now recently used.
        
        // Causing the size to grow to 12 should evict 'a'.
        assertSuccessOnSetDataForKey("f", value0: "f", value1: "f")
        // Causing the size to grow to 12 should evict 'c'.
        assertSuccessOnSetDataForKey("g", value0: "g", value1: "g")
        assertNilSnapshotForKey("a")
        assertNilSnapshotForKey("c")
        XCTAssertEqual(10, self.cache.size)
        
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
        assertOnGetSnapshotForKey("d", value0: "d", value1: "d")
        assertOnGetSnapshotForKey("e", value0: "e", value1: "e")
        assertOnGetSnapshotForKey("f", value0: "f", value1: "f")
        assertOnGetSnapshotForKey("g", value0: "g", value1: "g")
    }
    
    func testEvictionHonorsLruFromPreviousSession() {
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
        assertSuccessOnSetDataForKey("c", value0: "c", value1: "c")
        assertSuccessOnSetDataForKey("d", value0: "d", value1: "d")
        assertSuccessOnSetDataForKey("e", value0: "e", value1: "e")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")// 'b' is now recently used.
        
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        
        // Causing the size to grow to 12 should evict 'a'.
        assertSuccessOnSetDataForKey("f", value0: "f", value1: "f")
        // Causing the size to grow to 12 should evict 'c'.
        assertSuccessOnSetDataForKey("g", value0: "g", value1: "g")
        assertNilSnapshotForKey("a")
        assertNilSnapshotForKey("c")
        XCTAssertEqual(10, self.cache.size)
        
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
        assertOnGetSnapshotForKey("d", value0: "d", value1: "d")
        assertOnGetSnapshotForKey("e", value0: "e", value1: "e")
        assertOnGetSnapshotForKey("f", value0: "f", value1: "f")
        assertOnGetSnapshotForKey("g", value0: "g", value1: "g")
    }
    
    func testCacheSingleEntryOfSizeGreaterThanMaxSize() {
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        assertSuccessOnSetDataForKey("a", value0: "aaaaa", value1: "aaaaaa")
        assertNilSnapshotForKey("a")
    }
    
    func testCacheSingleValueOfSizeGreaterThanMaxSize() {
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        assertSuccessOnSetDataForKey("a", value0: "aaaaaaaaaaa", value1: "a")
        assertNilSnapshotForKey("a")
    }
    
    func testRemoveAbsentElement() {
        assertSuccessOnRemoveEntryForKey("a", isRemoved: false)
        assertJournalBodyEquals()
    }
    
    func testRebuildJournalOnRepeatedReads() {
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
        
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
        
        var lastJournalLength: Int64 = 0
        while true {
            let journalLen = try! Utils.getFileSizeAtPath(self.journalFile)
            
            assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
            assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
            
            if (journalLen < lastJournalLength) {
                print("Journal compacted from \(lastJournalLength) bytes to \(journalLen) bytes")
                break
            }
            
            if (self.cache.getRedundantOperationCountInJournal() > self.cache.getRedundantOperationsCompactThreshold()) {
                XCTFail()
                break
            }
            
            lastJournalLength = journalLen
        }
        
        // Sanity check that a rebuilt journal behaves normally.
        assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
    }
    
    func testRebuildJournalOnRepeatedEdits() {
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
        
        var lastJournalLength: Int64 = 0
        while true {
            let journalLen = try! Utils.getFileSizeAtPath(self.journalFile)
            
            assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
            assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
            
            if (journalLen < lastJournalLength) {
                print("Journal compacted from \(lastJournalLength) bytes to \(journalLen) bytes")
                break
            }
            
            if (self.cache.getRedundantOperationCountInJournal() > self.cache.getRedundantOperationsCompactThreshold()) {
                XCTFail()
                break
            }
            
            lastJournalLength = journalLen
        }
        
        assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
    }
    
    func testRebuildJournalOnRepeatedReadsWithOpenAndClose() {
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
        
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
        
        var lastJournalLength: Int64 = 0
        while true {
            let journalLen = try! Utils.getFileSizeAtPath(self.journalFile)
            
            assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
            assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
            
            assertSuccessOnCloseCache(self.cache)
            self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
            
            if (journalLen < lastJournalLength) {
                print("Journal compacted from \(lastJournalLength) bytes to \(journalLen) bytes")
                break
            }
            
            if (self.cache.getRedundantOperationCountInJournal() > self.cache.getRedundantOperationsCompactThreshold()) {
                XCTFail()
                break
            }
            
            lastJournalLength = journalLen
        }
        
        // Sanity check that a rebuilt journal behaves normally.
        assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
    }
    
    func testRebuildJournalOnRepeatedEditsWithOpenAndClose() {
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
        
        assertSuccessOnCloseCache(self.cache)
        self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
        
        var lastJournalLength: Int64 = 0
        while true {
            let journalLen = try! Utils.getFileSizeAtPath(self.journalFile)
            
            assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
            assertSuccessOnSetDataForKey("b", value0: "b", value1: "b")
            
            assertSuccessOnCloseCache(self.cache)
            self.cache = newDiskLRUCacheInstance(redundantOpThreshold: 200)
            
            if (journalLen < lastJournalLength) {
                print("Journal compacted from \(lastJournalLength) bytes to \(journalLen) bytes")
                break
            }
            
            if (self.cache.getRedundantOperationCountInJournal() > self.cache.getRedundantOperationsCompactThreshold()) {
                XCTFail()
                break
            }
            
            lastJournalLength = journalLen
        }
        
        // Sanity check that a rebuilt journal behaves normally.
        assertOnGetSnapshotForKey("a", value0: "a", value1: "a")
        assertOnGetSnapshotForKey("b", value0: "b", value1: "b")
    }
    
    
    func testRestoreBackupFile() {
        assertSuccessOnSetDataForKey("k1", value0: "ABC", value1: "DE")
        assertSuccessOnCloseCache(self.cache)
        
        try! Utils.renamePath(self.journalFile, toPath: self.journalBkpFile, deleteDestination: false)
        assertFileExists(self.journalBkpFile)
        assertFileNotExists(self.journalFile)
        
        self.cache = newDiskLRUCacheInstance()
        assertOnGetSnapshotForKey("k1", value0: "ABC", value1: "DE")
        assertFileNotExists(self.journalBkpFile)
        assertFileExists(self.journalFile)
    }
    
    func testJournalFileIsPreferredOverBackupFile() {
        assertSuccessOnSetDataForKey("k1", value0: "ABC", value1: "DE")
        
        assertFileNotExists(self.journalBkpFile)
        
        let fileManager = NSFileManager.defaultManager()
        try! fileManager.copyItemAtPath(self.journalFile, toPath: self.journalBkpFile)
        
        assertSuccessOnSetDataForKey("k2", value0: "F", value1: "GH")
        assertSuccessOnCloseCache(self.cache)
        
        assertFileExists(self.journalBkpFile)
        assertFileExists(self.journalFile)
        
        self.cache = newDiskLRUCacheInstance()
        assertOnGetSnapshotForKey("k1", value0: "ABC", value1: "DE")
        assertOnGetSnapshotForKey("k2", value0: "F", value1: "GH")
        
        assertFileNotExists(self.journalBkpFile)
        assertFileExists(self.journalFile)
    }
    
    func testOpenCreatesDirectoryIfNecessary() {
        assertSuccessOnCloseCache(self.cache)
        
        let oldCacheDir = self.cacheDir
        self.cacheDir = oldCacheDir + "/testOpenCreatesDirectoryIfNecessary"
        assertFileNotExists(self.cacheDir)
        
        self.cache = newDiskLRUCacheInstance()
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        assertFileExists(self.cacheDir + "/a.0")
        assertFileExists(self.cacheDir + "/a.1")
        assertFileExists(self.cacheDir + "/journal")
    }
    
    func testFileDeletedExternally() {
        assertSuccessOnSetDataForKey("a", value0: "a", value1: "a")
        
        let a1path = self.cacheDir + "/a.1"
        assertFileExists(a1path)
        let fileManager = NSFileManager.defaultManager()
        try! fileManager.removeItemAtPath(a1path)
        
        assertNilSnapshotForKey("a")
    }
    
    func testExistingSnapshotStillValidAfterEntryEvicted() {
        assertSuccessOnCloseCache(self.cache)
        
        self.cache = newDiskLRUCacheInstance(maxSize: 10)
        assertSuccessOnSetDataForKey("a", value0: "aa", value1: "aaa")
        guard let snapshotA = assertOnGetSnapshotForKey("a", value0: "aa", value1: "aaa") else {
            XCTFail()
            return
        }
        
        assertSuccessOnSetDataForKey("b", value0: "bb", value1: "bbb") // size 10 reached
        assertSuccessOnSetDataForKey("c", value0: "cc", value1: "ccc") // size 5; will evict 'a'
        assertNilSnapshotForKey("a")
        
        XCTAssertEqual(snapshotA.getStringDataAtIndex(0, encoding: NSUTF8StringEncoding), "aa")
        XCTAssertEqual(snapshotA.getStringDataAtIndex(1, encoding: NSUTF8StringEncoding), "aaa")
    }
    
    func testUsingNSOutputStreamAfterFileDeleted() {
        let path = self.cacheDir + "/testOutputStream"
        assertFileNotExists(path)
        let outputStream = NSOutputStream(toFileAtPath: path, append: true)
        
        outputStream?.open()
        try! outputStream?.IA_write("test line\n")
        assertFileExists(path)
        
        try! Utils.deleteFileIfExistsAtPath(path)
        assertFileNotExists(path)
        
        do {
            try outputStream?.IA_write("second test line\n") //no error. TODO: handle the error using a custom NSStreamDelegate
            
            XCTAssertNil(outputStream?.delegate)
        } catch {
            XCTFail()
        }

    }
    
    func testCacheDelete() {
        assertSuccessOnSetDataForKey("a", value0: "aa", value1: "aaa")
        assertFileExists(self.journalFile)
        
        assertSuccessOnDeleteCache()
        assertFileNotExists(self.cacheDir)
        XCTAssertTrue(self.cache.isClosed())
    }

    
    func testAggressiveClearingHandlesReadWriteRemoveKeyAndClose() {
        assertSuccessOnSetDataForKey("a", value0: "aa", value1: "aaa")
        assertSuccessOnSetDataForKey("c", value0: "cc", value1: "ccc")
        assertSuccessOnSetDataForKey("b", value0: "bb", value1: "bbb") // wait async operations to finish, or deleting cache dir may fail
        
        let fileManager = NSFileManager.defaultManager()
        do {
            try fileManager.removeItemAtPath(self.cacheDir)
        } catch {
            print("------------  delete failed")
            XCTFail()
        }

        assertFileNotExists(self.cacheDir)
        
        // all public APIs should be tested after the cache dir was removed externally.
        // the method delete call is not included below, since it will also close the cache
        
        assertErrorOnSetDataForKey("d", value0: "dd", value1: "ddd")
        assertErrorOnSetPartialDataForKey("a", value: "a0", index: 0, cache: self.cache)
        assertSuccessOnRemoveEntryForKey("b", isRemoved: true) // TODO: isRemoved should be false if NSStreamDelegate is added for the journalWriter.
        
        assertNilSnapshotForKey("a")
        assertNilSnapshotForKey("b")
        assertNilSnapshotForKey("c")
        assertNilSnapshotForKey("d")
        
        //test close
        assertSuccessOnCloseCache(self.cache)
        
        assertFileNotExists(self.cacheDir)
    }
    
    func testAggressiveClearingHandlesDelete() {
        assertSuccessOnSetDataForKey("a", value0: "aa", value1: "aaa")
        assertSuccessOnSetDataForKey("c", value0: "cc", value1: "ccc")
        assertSuccessOnSetDataForKey("b", value0: "bb", value1: "bbb") // wait async operations to finish, or deleting cache dir may fail
        
        let fileManager = NSFileManager.defaultManager()
        do {
            try fileManager.removeItemAtPath(self.cacheDir)
        } catch {
            print("------------  delete failed")
            XCTFail()
        }
        
        assertFileNotExists(self.cacheDir)
        
        // all public APIs should be tested after the cache dir was removed externally.
        
        assertNilSnapshotForKey("a")
        assertNilSnapshotForKey("b")
        assertNilSnapshotForKey("c")
        assertNilSnapshotForKey("d")
        
        assertSuccessOnDeleteCache()
        XCTAssertTrue(self.cache.isClosed())
        assertFileNotExists(self.cacheDir)
    }
    
    func testRemoveHandlesMissingFile() {
        assertSuccessOnSetDataForKey("a", value0: "aa", value1: "aaa")
        
        let cleanFile0 = getCleanFilePathForKey("a", index: 0)
        assertFileExists(cleanFile0)
        
        try! Utils.deleteFileIfExistsAtPath(cleanFile0)
        assertFileNotExists(cleanFile0)
        
        assertSuccessOnRemoveEntryForKey("a", isRemoved: true)
        
    }
}
