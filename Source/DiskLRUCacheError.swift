//
//  DiskLRUCacheError.swift
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

enum DiskLRUCacheError: ErrorType {
    case IOException(desc: String)
    case BadFormat(desc: String)
    case IllegalStateException(desc: String)
}

/**
 Error codes for NSError returned by the async methods in class DiskLRUCache like getSnapshotForKey.
 */
public enum DiskLRUCacheErrorCode: Int {
    case ErrorCodeIOException
    case ErrorCodeBadFormat
    case ErrorCodeIllegalStateException
}
