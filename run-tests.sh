#!/usr/bin/env bash

set -e

xcodebuild clean test -workspace SwiftyCache.xcworkspace -scheme SwiftyCache-iOS -destination "platform=iOS Simulator,name=iPhone 4s" -destination "platform=iOS Simulator,name=iPhone 6 Plus" -enableCodeCoverage YES
xcodebuild clean test -workspace SwiftyCache.xcworkspace -scheme SwiftyCache-OSX -sdk macosx -enableCodeCoverage YES
xcodebuild clean test -workspace SwiftyCache.xcworkspace -scheme SwiftyCache-tvOS -destination "platform=tvOS Simulator,name=Apple TV 1080p" -enableCodeCoverage YES

