//
//  Utils.swift
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

class Utils {
    
    static func getFileSizeAtPath(path: String) throws -> Int64 {
        let attr = try NSFileManager.defaultManager().attributesOfItemAtPath(path)
        
        if let fileSize = attr[NSFileSize]  {
            return (fileSize as! NSNumber).longLongValue
        } else {
            throw DiskLRUCacheError.IOException(desc: "Failed to get file size at path: \(path)")
        }
    }
    
    
    static func deleteFileIfExistsAtPath(filePath: String) throws {
        let fileManager = NSFileManager.defaultManager()
        if fileManager.fileExistsAtPath(filePath) {
            try fileManager.removeItemAtPath(filePath)
        }
    }
    
    static func renamePath(from: String, toPath dest: String, deleteDestination: Bool) throws {
        if (deleteDestination) {
            try deleteFileIfExistsAtPath(dest)
        }
        
        let fileManager = NSFileManager.defaultManager()
        try fileManager.moveItemAtPath(from, toPath: dest)
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
}
