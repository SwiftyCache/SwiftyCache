//
//  DiskLRUCache.swift
//  SwiftyCache
//
//  Created by Haoming Ma on 16/02/2016.
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

private let JOURNAL_FILE: String = "journal"
private let JOURNAL_FILE_TEMP: String = "journal.tmp"
private let JOURNAL_FILE_BACKUP: String = "journal.bkp"

private let NL = "\n"
private let MAGIC = "io.github.swiftycache.DiskLRUCache"
private let VERSION_1 = "1"

private let ANY_SEQUENCE_NUMBER: Int64 = -1

private let CLEAN = "CLEAN"
private let DIRTY = "DIRTY"
private let REMOVE = "REMOVE"
private let READ = "READ"

private let DEFAULT_REDUNDANT_OPERATIONS_COMPACT_THRESHOLD = 2000

public class DiskLRUCache {

    // MARK: internal properties
    private let cacheDir: String
    
    private let journalPath: String
    private let journalTmpPath: String
    private let journalBackupPath: String
    
    private let cacheVersion: Int
    let valueCount: Int
    private var journalWriter: NSOutputStream?
    private let lruEntries: LinkedDictionary<String, CacheEntry>
    
    private let cacheSerialQueue : dispatch_queue_t
    
    private var redundantOpCount: Int = 0
    
    private var redundantOpCompactThreshold = DEFAULT_REDUNDANT_OPERATIONS_COMPACT_THRESHOLD
    
    /**
    * To differentiate between old and current snapshots, each entry is given
    * a sequence number each time an edit is committed. A snapshot is stale if
    * its sequence number is not equal to its entry's sequence number.
    */
    private var nextSequenceNumber: Int64 = 0
    
    private let validKeyRegex: NSRegularExpression
    
    private var lastAsyncError: NSError?
    

    // MARK: public
    public private(set) var maxSize: Int64
    public private(set) var size: Int64 = 0
    
    
    /**
     Open the cache in the directory specified, creating a cache if none exists there.
     
     - parameter cacheDir:     The path of the cache directory. The directory will be created if it does not exits before.
     - parameter cacheVersion: The version number of the cache, which will be stored as cache metadata used for format compatibility checks.
     - parameter valueCount:   The number of values/fields per cache entry. Must be positive.
     - parameter maxSize:      The maximum number of bytes this cache should use to store.
     */
    public init(cacheDir: String, cacheVersion: Int, valueCount: Int, maxSize: Int64) {
        self.cacheDir = cacheDir
        self.cacheVersion = cacheVersion
        self.valueCount = valueCount
        self.maxSize = maxSize
        
        precondition(valueCount > 0, "valueCount must be greater than 0")
        precondition(maxSize > 0, "maxSize must be greater than 0")
        
        let queueName = "io.github.swiftycache.DiskLRUCache." + self.cacheDir
        self.cacheSerialQueue = dispatch_queue_create(queueName, DISPATCH_QUEUE_SERIAL)

        
        self.journalPath = (cacheDir as NSString).stringByAppendingPathComponent(JOURNAL_FILE)
        self.journalTmpPath = (cacheDir as NSString).stringByAppendingPathComponent(JOURNAL_FILE_TEMP)
        self.journalBackupPath = (cacheDir as NSString).stringByAppendingPathComponent(JOURNAL_FILE_BACKUP)
        
        let dummyEntry = CacheEntry.dummyValue()
        self.lruEntries = LinkedDictionary<String, CacheEntry>(dummyKey: "", dummyValue: dummyEntry, initialCapacity: 16, accessOrder: true)
        
        self.validKeyRegex = try! NSRegularExpression(pattern: "^[a-z0-9_-]{1,120}$", options: .CaseInsensitive)
        
        dispatch_async(cacheSerialQueue) {
            do {
                try self.open()
            } catch let error as NSError {
                self.lastAsyncError = error
                NSLog("[init] error when opening the cache: \(self.lastAsyncError)")
            }
        }
    }
    
    /**
     Writes values for all fields of a cache entry with a key specified. It will create the key and an entry of the values if the key does not exists in the cache before.
     
     - parameter data:                           An array of values for all field of an entry, and its length must be equal to the value count of a cache entry.
     - parameter key:                            The key of the entry to write.
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler.
     */
    public func setData(data: [NSData], forKey key: String, shouldRunHandlersInMainQueue: Bool = true, errorHandler: NSError -> (), completionHandler: () -> ()) {
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> () in
            try self.syncSetDataForKey(key, data: data)
        }
    }
    
    /**
     Writes values (maybe not all fields) on an exsiting cache entry with a key specified.
     
     - parameter data:                           An array of tuples (new data, value field index), and its length must not be greater than the value count of a cache entry.
     - parameter key:                            The existing key of the entry to write.
     - parameter readIndex:                      A boolean array of the same length with the value count of each cache entry, to indicate if a value in the corresponding index should be read into the snapshot or not.
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler.
     */
    public func setPartialData(data: [(NSData, Int)], forExistingKey key: String, shouldRunHandlersInMainQueue: Bool = true, errorHandler: NSError -> (), completionHandler: () -> ()) {
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> () in
            try self.syncSetPartialData(data, forExistingKey: key)
        }
    }
    
    /**
     Gets a cache entry snapshot for a key specified.
     
     - parameter key:                            The key of the entry to read.
     - parameter readIndex:                      A boolean array of the same length with the value count of each cache entry, to indicate if a value in the corresponding index should be read into the snapshot or not.
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler. The argument will be the CacheEntrySnapshot if the key specified exists in the cache, or will be nil.
     */
    public func getSnapshotForKey(key: String, readIndex: [Bool], shouldRunHandlersInMainQueue: Bool = true, errorHandler: NSError -> (), completionHandler: CacheEntrySnapshot? -> ()) {
        
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> CacheEntrySnapshot? in
            return try self.syncGetSnapshotForKey(key, readIndex: readIndex)
        }
    }
    
    /**
     Removes a cache entry for a key specified.
     
     - parameter key:                            The key of the entry to remove.
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler. The argument will be true if the entry was removed, or false if no entry was found for the key specified.
     */
    public func removeEntryForKey(key: String, shouldRunHandlersInMainQueue: Bool = true, errorHandler: NSError -> (), completionHandler: Bool -> ()) {
        
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> Bool in
            return try self.syncRemoveEntryForKey(key)
        }
    }
    
    /**
     Closes the cache asynchronously.
     
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler.
     */
    public func close(shouldRunHandlersInMainQueue shouldRunHandlersInMainQueue: Bool = true, errorHandler: (NSError) -> (), completionHandler: () -> ()) {
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> () in
            try self.syncClose()
        }
    }
    
    /**
     Closes the cache synchronously.
     
     - throws: error if it failed to close the cache or any other unhandled error, e.g. an IO error happened when the cache was pruning old entries in the background.
     */
    public func close() throws {
        NSLog("[close] cache dir: \(self.cacheDir)")
        
        var exception: NSError?
        dispatch_sync(cacheSerialQueue) {
            if let error = self.lastAsyncError {
                NSLog("found error from last async operation: \(error)")
                self.lastAsyncError = nil
                
                exception = error
            } else {
                do {
                    try self.syncClose()
                } catch let error as NSError {
                    exception = error
                }
            }
        }
        
        if let error = exception {
            throw error
        }
    }
    
    /**
     Closes the cache and deletes all of its stored values. This will delete all files in the cache directory including files that weren't created by the cache.
     
     - parameter shouldRunHandlersInMainQueue:   If true then the errorHandler and the completionHandler will be invoked in the main queue, otherwise will be in the calling queue. It is true by default.
     - parameter errorHandler:                   The error handler.
     - parameter completionHandler:              The completion handler.
     */
    public func delete(shouldRunHandlersInMainQueue shouldRunHandlersInMainQueue: Bool = true, errorHandler: NSError -> (), completionHandler: () -> ()) {
        self.performBlock(completionHandler: completionHandler, errorHandler: errorHandler, shouldRunHandlersInMainQueue: shouldRunHandlersInMainQueue) { () -> () in
            try self.syncDelete()
        }
    }
    
    /**
     Returns true if this cache has been closed.
     
     - returns: The cache is closed or not.
     */
    public func isClosed() -> Bool {
        var closed = true
        dispatch_sync(self.cacheSerialQueue) {
            closed = self.journalWriter == nil
        }
        return closed
    }
    
    // MARK: internal implementation
    
    deinit {
        if (isClosed()) {
            return
        } else {
            NSLog("[deinit] closing DiskLRUCache in \(self.cacheDir)")
            do {
                try self.close()
            } catch let error as NSError {
                NSLog("[deinit] error when closing the cache: \(error)")
            }
        }
    }
    
    private func open() throws {
        NSLog("[open] ...")
        let fileManager = NSFileManager.defaultManager()
        try fileManager.createDirectoryAtPath(cacheDir, withIntermediateDirectories: true, attributes: nil)
        
        let journalUrl = (cacheDir as NSString).stringByAppendingPathComponent(JOURNAL_FILE)
        let journalBackupUrl = (cacheDir as NSString).stringByAppendingPathComponent(JOURNAL_FILE_BACKUP)
        
        if (fileManager.fileExistsAtPath(journalBackupUrl)) {
            
            // If journal file also exists just delete backup file.
            if (fileManager.fileExistsAtPath(journalUrl)) {
                try fileManager.removeItemAtPath(journalBackupUrl)
            } else {
                // If a bkp file exists but without journal file, use it instead.
                NSLog("[open] use journal backup")
                try fileManager.moveItemAtPath(journalBackupUrl, toPath: journalUrl)
            }
        }
        
        // Prefer to pick up where we left off.
        if (fileManager.fileExistsAtPath(journalUrl)) {
            
            do {
                try self.readJournal()
                try self.processJournal()
                NSLog("[open] cache opened")
                return
            } catch let error as NSError {
                NSLog("DiskLruCache \(cacheDir) is corrupt: \(error). \nWill create a new empty cache.")
                try self.syncDelete()
                try fileManager.createDirectoryAtPath(cacheDir, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        // rebuild a new empty cache.
        try self.rebuildJournal()
        NSLog("[open] empty cache opened")
    }
    
    
    internal func getCleanFilePathForKey(key: String, index: Int) -> String {
        return (self.cacheDir as NSString).stringByAppendingPathComponent(key + ".\(index)")
    }
    
    internal func getDirtyFilePathForKey(key: String, index: Int) -> String {
        return (self.cacheDir as NSString).stringByAppendingPathComponent(key + ".\(index).tmp")
    }

    
    private func readJournal() throws {
        guard let reader = StreamReader(path: self.journalPath) else {
            NSLog("[readJournal] Failed to open journal")
            throw DiskLRUCacheError.IOException(desc: "Failed to open journal: \(self.journalPath)")
        }
        
        defer {
            reader.close()
        }
        
        guard let magic = reader.nextLine(),
            version = reader.nextLine(),
            cacheVersionString = reader.nextLine(),
            valueCountString = reader.nextLine(),
            blank = reader.nextLine()
            where MAGIC == magic
                && VERSION_1 == version
                && String(self.cacheVersion) == cacheVersionString
                && String(self.valueCount) == valueCountString
                && "" == blank
        else {
            NSLog("[readJournal] Bad journal file header 1")
            throw DiskLRUCacheError.BadFormat(desc: "Bad journal file header 1")
        }
        
        var lineCount:Int = 0;
        while (true) {
            if let line = reader.nextLine() {
                try readJournalLine(line)
                lineCount += 1
            } else {
                break
            }
        }
        
        self.redundantOpCount = lineCount - self.lruEntries.count()
        // If we ended on a truncated line, rebuild the journal before appending to it.
        if (reader.hasUnterminatedLine()) {
            NSLog("[readJournal] journal not ended with NL, so rebuild the journal ...")
            try rebuildJournal()
        } else {
            try self.initJournalWriter()
        }

    }
    
    private func initJournalWriter() throws {
        if (self.journalWriter != nil) {
            self.journalWriter!.close()
        }
        
//        let fileManager = NSFileManager.defaultManager()
//        if (!fileManager.fileExistsAtPath(self.journalPath)) {
//            fileManager.createFileAtPath(self.journalPath, contents: nil, attributes: nil)
//        }
        
        self.journalWriter = NSOutputStream(toFileAtPath: self.journalPath, append: true)
        if (self.journalWriter == nil) {
            throw DiskLRUCacheError.IOException(desc: "Failed to open \(self.journalPath)")
        }
        
        self.journalWriter!.open()
        NSLog("[initJournalWriter] journalWriter opened")
    }
    
    private func parseLengths(lensStr: String) throws -> [Int64] {
        let lens = lensStr.characters.split{$0 == " "}.map(String.init)
        if lens.count != self.valueCount {
            NSLog("Unmatched length count: " + lensStr)
            throw DiskLRUCacheError.BadFormat(desc: "Unmatched length count: " + lensStr)
        }
        
        return try lens.map {
            (str) -> Int64 in
            if let v = Int64(str) {
                return v
            } else {
                NSLog("Bad integer \(str) in lengths string: " + lensStr)
                throw DiskLRUCacheError.BadFormat(desc: "Bad integer: \(str) in " + lensStr)
            }
        }
    }
    
    
    private func readJournalLine(line: String) throws {
        guard let firstSpace: Range<String.Index> = line.rangeOfString(" ") else {
            NSLog("unexpected journal line: " + line)
            throw DiskLRUCacheError.BadFormat(desc: "unexpected journal line: " + line)
        }
        
        let statusStr = line.substringToIndex(firstSpace.startIndex)
        
        let keyBegin = firstSpace.endIndex
        
        let secSpaceSearchRang: Range<String.Index> = keyBegin ..< line.endIndex
        let secondSpace = line.rangeOfString(" ", options: NSStringCompareOptions.LiteralSearch, range: secSpaceSearchRang)
        
        var key: String
        if secondSpace == nil {
            key = line.substringFromIndex(keyBegin)
            
            if (statusStr == REMOVE) {
                lruEntries.removeValueForKey(key)
                return;
            }
            
        } else {
            key = line.substringWithRange(keyBegin ..< secondSpace!.startIndex)
        }
        
        
        var entry = self.lruEntries.get(key)
        
        if (entry == nil) {
            entry = CacheEntry(key: key, valueCount: self.valueCount)
            self.lruEntries.updateValue(entry!, forKey: key)
        }
        
        if (secondSpace != nil && CLEAN == statusStr) {
            let lens = try self.parseLengths(line.substringFromIndex(secondSpace!.endIndex))
            entry!.readable = true
            entry!.currentEditor = nil
            entry!.setLengths(lens)
        } else if (secondSpace == nil && DIRTY == statusStr) {
            entry!.currentEditor = CacheEntryEditor(lruCache: self, entry: entry!)
        } else if (secondSpace == nil && READ == statusStr) {
            // This work was already done by calling lruEntries.get().
        } else {
            NSLog("unexpected journal line: " + line)
            throw DiskLRUCacheError.BadFormat(desc: "unexpected journal line: " + line)
        }
    }
    
    private func processJournal() throws {
        try Utils.deleteFileIfExistsAtPath(self.journalTmpPath)
        for (key, entry) in self.lruEntries {
            assert(key == entry.key)
            if entry.currentEditor == nil {
                for t in 0 ..< self.valueCount {
                    self.size += entry.lengths[t]
                }
            } else {
                entry.currentEditor = nil // set currentEditor into null
                for t in 0 ..< self.valueCount {
                    try Utils.deleteFileIfExistsAtPath(self.getCleanFilePathForKey(key, index: t))
                    try Utils.deleteFileIfExistsAtPath(self.getDirtyFilePathForKey(key, index: t))
                }
                self.lruEntries.removeValueForKey(key)
            }
        }
        
    }
    
    private func rebuildJournal() throws {
        NSLog("[rebuildJournal] ...")
        if let writer = self.journalWriter {
            writer.close()
            self.journalWriter = nil
        }
        
        guard let tmpWriter = NSOutputStream(toFileAtPath: self.journalTmpPath, append: false) else {
            throw DiskLRUCacheError.IOException(desc: "Failed to open temp journal file: " + self.journalTmpPath)
        }
        
        tmpWriter.open()
        
        let str = MAGIC + NL + VERSION_1 + NL + "\(self.cacheVersion)\(NL)\(self.valueCount)\(NL)\(NL)"
        try tmpWriter.IA_write(str)
        
        for (key, entry) in self.lruEntries {
            if entry.currentEditor != nil {
                try tmpWriter.IA_write(DIRTY + " " + key + NL)
            } else {
                try tmpWriter.IA_write(CLEAN + " " + key + " " + entry.getLengths() + NL)
            }
        }
        
        tmpWriter.close()
        
        
        let fileManager = NSFileManager.defaultManager()
        if fileManager.fileExistsAtPath(self.journalPath) {
            try Utils.renamePath(self.journalPath, toPath: self.journalBackupPath, deleteDestination: true)
        }
        
        try Utils.renamePath(journalTmpPath, toPath: self.journalPath, deleteDestination: false)
        
        if fileManager.fileExistsAtPath(self.journalBackupPath) {
            try fileManager.removeItemAtPath(self.journalBackupPath)
        }
        
        try self.initJournalWriter()
    }
    
    private func checkNotClosed() throws {
        if (self.journalWriter == nil) {
            throw DiskLRUCacheError.IOException(desc: "cache is closed")
        }
    }

    func isValidKey(key: String) -> Bool {
        let wholeRange = NSMakeRange(0, key.characters.count)
        let matchedRange = validKeyRegex.rangeOfFirstMatchInString(key, options: NSMatchingOptions(rawValue: 0), range: wholeRange)
        
        // A wrong pattern "^[^\\s]{1,120}$" was used before, which allows characters like 😄 as key, but it allows "/" which causes problem using as a file name.
        // But when the wrong pattern was used, I found a bug in NSRegularExpression. To reproduce the bug, validKeyRegex should be initilised as follows before calling isValidKey:
        //
        // validKeyRegex = try! NSRegularExpression(pattern: "^[^\\s]{1,120}$", options: .AllowCommentsAndWhitespace)
        //
        // Then print logs here:
        //
        //print("\(key), matched loc: \(matchedRange.location), len: \(matchedRange.length)")
        //print("\(key), wholeRange loc: \(wholeRange.location), len: \(wholeRange.length)")
        /*
        😄, matched loc: 0, len: 2          ---  seems a bug in NSRegularExpression
        😄, wholeRange loc: 0, len: 1
        😄😄, matched loc: 0, len: 2        --- correct here
        😄😄, wholeRange loc: 0, len: 2
        😄😄😄, matched loc: 0, len: 4     ---  seems a bug in NSRegularExpression
        😄😄😄, wholeRange loc: 0, len: 3
        
        So we use >= rather than == for "matchedRange.length >= wholeRange.length" below
        */
        
        if (matchedRange.length >= wholeRange.length && matchedRange.location == wholeRange.location) {
            return true
        } else {
            return false
        }
    }
    
    private func validateKey(key: String) throws {
        guard self.isValidKey(key) else {
            throw DiskLRUCacheError.BadFormat(desc: "Invalid key: \(key)")
        }
    }
    
    func editKey(key: String) throws -> CacheEntryEditor {
        try checkNotClosed()
        try validateKey(key)

        var entry = self.lruEntries.get(key)
        
        if (entry == nil) {
            entry = CacheEntry(key: key, valueCount: self.valueCount)
            self.lruEntries.updateValue(entry!, forKey: key)
        }
        
        assert(entry!.currentEditor == nil)
 
        let editor = CacheEntryEditor(lruCache: self, entry: entry!)
        entry!.currentEditor = editor

        // Flush the journal before creating files to prevent file leaks.
        try self.journalWriter!.IA_write(DIRTY + " " + key + NL)
        return editor
    }
    
    
    func syncCommitEditor(editor: CacheEntryEditor) throws {
        if (editor.hasErrors) {
            try self.syncAbortEditor(editor)
        } else {
            try self.completeEdit(editor, success: true)
        }
    }
    
    
    func syncAbortEditor(editor: CacheEntryEditor) throws {
        let key = editor.entry.key // the next line can remove the entry in the cache, so we get the key first before self.entry becomes a dangling pointer.
        try self.completeEdit(editor, success: false)
        try self.syncRemoveEntryForKey(key) // The previous entry is stale.
    }

    
    func completeEdit(editor: CacheEntryEditor, success: Bool) throws {
        let entry = editor.entry
        assert(entry.currentEditor === editor)
        
        let fileManager = NSFileManager.defaultManager()

        // If this edit is creating the entry for the first time, every index must have a value.
        if (success && !entry.readable) {
            for i in 0 ..< valueCount {
                if (!editor.written![i]) {
                    try self.syncAbortEditor(editor)
                    throw DiskLRUCacheError.IllegalStateException(desc: "Newly created entry didn't create value for index: \(i)")
                }
                
                let dirtyFilePath = self.getDirtyFilePathForKey(entry.key, index: i)
                if (!fileManager.fileExistsAtPath(dirtyFilePath)) {
                    try self.syncAbortEditor(editor)
                    return
                }
            }
        }

        for i in 0 ..< valueCount {
            let dirty = self.getDirtyFilePathForKey(entry.key, index: i)
            if (success) {
                if (NSFileManager.defaultManager().fileExistsAtPath(dirty)) {
                    let clean = self.getCleanFilePathForKey(entry.key, index: i)

                    try Utils.renamePath(dirty, toPath: clean, deleteDestination: true)
                    
                    let oldLength = entry.lengths[i]
                    let newLength = try Utils.getFileSizeAtPath(clean)
                    entry.lengths[i] = newLength
                    self.size = self.size - oldLength + newLength
                }
            } else {
                try Utils.deleteFileIfExistsAtPath(dirty)
            }
        }

        self.redundantOpCount += 1
        entry.currentEditor = nil
        if (entry.readable || success) {
            entry.readable = true
            try self.journalWriter!.IA_write(CLEAN + " " + entry.key + " " + entry.getLengths() + NL)
            if (success) {
                entry.sequenceNumber = nextSequenceNumber
                nextSequenceNumber += 1
            }
        } else {
            self.lruEntries.removeValueForKey(entry.key)
            try self.journalWriter!.IA_write(REMOVE + " " + entry.key + NL)
        }
    
        if (self.size > self.maxSize || journalRebuildRequired()) {
            self.asyncCleanup()
        }
    }
    
    /**
    * We only rebuild the journal when it will halve the size of the journal
    * and eliminate at least 2000 ops.
    */
    private func journalRebuildRequired() -> Bool {
        return redundantOpCount >= redundantOpCompactThreshold && self.redundantOpCount >= self.lruEntries.count()
    }
    
    /**
    * Drops the entry for {@code key} if it exists and can be removed. Entries
    * actively being edited cannot be removed.
    *
    * @return true if an entry was removed.
    */
    
    func syncRemoveEntryForKey(key: String, shouldCleanupIfNecessary: Bool = true) throws -> Bool {
        try checkNotClosed()
        try validateKey(key)

        guard let entry = lruEntries.get(key) where entry.currentEditor == nil else {
            return false
        }

        let fileManager = NSFileManager.defaultManager()
        for i in 0 ..< self.valueCount {
            let file = self.getCleanFilePathForKey(entry.key, index: i)
            
            if (fileManager.fileExistsAtPath(file)) {
                try fileManager.removeItemAtPath(file)
            }
            self.size -= entry.lengths[i]
            entry.lengths[i] = 0
        }
    
        self.redundantOpCount += 1
        try self.journalWriter!.IA_write(REMOVE + " " + key + NL)
        self.lruEntries.removeValueForKey(key)
    
        if (shouldCleanupIfNecessary && journalRebuildRequired()) {
            self.asyncCleanup()
        }
    
        return true
    }
    
    
    private func syncCleanup() throws {
        if (self.journalWriter == nil) {
            return // Closed.
        }
        try trimToSize()
        if (journalRebuildRequired()) {
            try rebuildJournal()
            self.redundantOpCount = 0
        }
    }
    
    // this method should only run in the cache serial queue to schedule an async operation in the same queue
    private func asyncCleanup() {
        assert(self.lastAsyncError == nil)
        
        self.performBlock(completionHandler: { () -> () in
            }, errorHandler: { (error: NSError) -> () in
                dispatch_sync(self.cacheSerialQueue) {
                    NSLog("Error happended when performing async cleanup: \(error)")
                    self.lastAsyncError = error
                }
                
            }, shouldRunHandlersInMainQueue: false) { () -> () in
                    try self.syncCleanup()
        }
    }
    
    
    /** Closes this cache. Stored values will remain on the filesystem. */
    private func syncClose() throws {
        if (self.journalWriter == nil) {
            NSLog("[syncClose] closed already")
            return
        }
        
        for (_, entry) in self.lruEntries {
            assert(entry.currentEditor == nil)
        }
        
        self.lruEntries.removeAll()

        self.journalWriter!.close()
        self.journalWriter = nil
        NSLog("[syncClose] closed")
    }
    
    private func trimToSize() throws {
        while (size > maxSize) {
            if let (key, _) = self.lruEntries.getEldestEntry() {
                
                // set shouldCleanupIfNecessary to false to avoid recursive calls
                try self.syncRemoveEntryForKey(key, shouldCleanupIfNecessary: false)
            }
        }
    }
    
    static func performErrorCallback(errorCallback: (NSError) -> (), forError error: NSError, inMainQueue: Bool) {
        if inMainQueue {
            dispatch_async(dispatch_get_main_queue()) {
                errorCallback(error)
            }
        } else {
            errorCallback(error)
        }
    }
    
    func performBlock<T>(completionHandler completionHandler: (T) -> (), errorHandler: (NSError) -> (),
        shouldRunHandlersInMainQueue: Bool = true,
        block: () throws -> (T)) {
        
        dispatch_async(cacheSerialQueue) {
            if let error = self.lastAsyncError {
                NSLog("found error from last async operation: \(error)")
                self.lastAsyncError = nil
                
                DiskLRUCache.performErrorCallback(errorHandler, forError: error, inMainQueue: shouldRunHandlersInMainQueue)
            } else {
                let errorDomain = "io.github.swiftycache.DiskLRUCache.DiskLRUCacheError"
                
                do {
                    let result = try block()
                    
                    if shouldRunHandlersInMainQueue {
                        dispatch_async(dispatch_get_main_queue()) {
                            completionHandler(result)
                        }
                    } else {
                        completionHandler(result)
                    }
                    
                } catch DiskLRUCacheError.BadFormat(let desc) {
                    let code = DiskLRUCacheErrorCode.ErrorCodeBadFormat.rawValue
                    let error = NSError(domain: errorDomain,
                                        code: code, userInfo: [NSLocalizedDescriptionKey: desc])
                    
                    DiskLRUCache.performErrorCallback(errorHandler, forError: error, inMainQueue: shouldRunHandlersInMainQueue)
                    
                } catch DiskLRUCacheError.IOException(let desc) {
                    let code = DiskLRUCacheErrorCode.ErrorCodeIOException.rawValue
                    let error = NSError(domain: errorDomain,
                                        code: code, userInfo: [NSLocalizedDescriptionKey: desc])
                    
                    DiskLRUCache.performErrorCallback(errorHandler, forError: error, inMainQueue: shouldRunHandlersInMainQueue)
                    
                } catch DiskLRUCacheError.IllegalStateException(let desc) {
                    let code = DiskLRUCacheErrorCode.ErrorCodeIllegalStateException.rawValue
                    let error = NSError(domain: errorDomain,
                                        code: code, userInfo: [NSLocalizedDescriptionKey: desc])
                    
                    DiskLRUCache.performErrorCallback(errorHandler, forError: error, inMainQueue: shouldRunHandlersInMainQueue)
                    
                } catch let error as NSError {
                    DiskLRUCache.performErrorCallback(errorHandler, forError: error, inMainQueue: shouldRunHandlersInMainQueue)
                }
            }
        }
    }
    
    private func syncDelete() throws {
        try self.syncClose()
        try Utils.deleteFileIfExistsAtPath(self.cacheDir)
    }
    
    
    /**
    * Returns a snapshot of the entry named {@code key}, or null if it doesn't
    * exist is not currently readable. If a value is returned, it is moved to
    * the head of the LRU queue.
    */
    private func syncGetSnapshotForKey(key: String, readIndex: [Bool]) throws -> CacheEntrySnapshot? {
        try self.checkNotClosed()
        try validateKey(key)
        
        assert(readIndex.count == self.valueCount)
        
        guard let entry = lruEntries.get(key) where entry.readable else {
            return nil
        }
        
        var i = -1
        let data = try? readIndex.map {
            (read: Bool) -> NSData? in
            i += 1
            if read {
                let cleanFilePath = self.getCleanFilePathForKey(key, index: i)
                return try NSData(contentsOfFile: cleanFilePath, options: NSDataReadingOptions.DataReadingUncached)
                // there should be a memory LRU cache on top of the disk cache, so here uses DataReadingUncached
            } else {
                return nil
            }
        }
        
        if (data == nil) {
            // exception thrown from try NSData(...)
            // A file must have been deleted externally!
            NSLog("Failed to read cached data for key: \(key). It seems that the cache was corrupt, e.g. a cache file was deleted externally")
            
            return nil
        } else {
            redundantOpCount += 1;
            try journalWriter?.IA_write(READ + " " + key + NL);
            if (journalRebuildRequired()) {
                self.asyncCleanup()
            }
            return CacheEntrySnapshot(key: key, sequenceNumber: entry.sequenceNumber, data: data!, lengths: entry.lengths)
        }
       
    }
    
    
    private func syncSetDataForKey(key: String, data: [NSData]) throws {
        assert(data.count == self.valueCount)
        
        let editor = try self.editKey(key)
        
        var index = 0
        for dataForIndex in data {
            guard editor.setValue(dataForIndex, forIndex: index) else {
                try self.syncAbortEditor(editor)
                throw DiskLRUCacheError.IOException(desc: "Failed to set value for key:\(key) index:\(index)")
            }
            
            index += 1
        }
        
        try self.syncCommitEditor(editor)
    }
    
    private func syncSetPartialData(data: [(NSData, Int)], forExistingKey key: String) throws {
        assert(data.count <= self.valueCount)
        
        let editor = try self.editKey(key)
        
        for (value, index) in data {
            guard editor.setValue(value, forIndex: index) else {
                try self.syncAbortEditor(editor)
                throw DiskLRUCacheError.IOException(desc: "Failed to set partial data for key:\(key) index:\(index)")
            }
        }
        
        try self.syncCommitEditor(editor)
    }
    
    internal func getRedundantOperationCountInJournal() -> Int {
        return self.redundantOpCount
    }
    
    
    internal func getRedundantOperationsCompactThreshold() -> Int {
        return self.redundantOpCompactThreshold
    }
    
    internal func setRedundantOpCompactThreshold(threshold: Int) {
        precondition(threshold > 10)
        self.redundantOpCompactThreshold = threshold
    }

}
