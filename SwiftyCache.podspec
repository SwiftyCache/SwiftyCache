Pod::Spec.new do |s|
  s.name        = "SwiftyCache"
  s.version     = "0.9.0"
  s.summary     = "SwiftyCache is a disk-based LRU cache library in Swift."
  s.homepage    = "https://github.com/SwiftyCache/SwiftyCache"
  s.license     = { :type => "Apache License, Version 2.0" }
  s.authors     = { "Haoming Ma" => "brightpony@gmail.com" }

  s.requires_arc = true
  s.osx.deployment_target = "10.9"
  s.ios.deployment_target = "8.0"
  s.source   = { :git => "https://github.com/SwiftyCache/SwiftyCache.git", :tag => s.version }
  s.source_files = "Source/*.swift"
end
