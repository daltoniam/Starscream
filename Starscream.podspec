Pod::Spec.new do |s|
  s.name         = "Starscream"
  s.version      = "0.9.1"
  s.summary      = "A conforming WebSocket RFC 6455 client library in Swift for iOS and OSX."
  s.homepage     = "https://github.com/daltoniam/Starscream"
  s.license      = 'Apache License, Version 2.0'
  s.author       = {'Dalton Cherry' => 'http://daltoniam.com', 'Austin Cherry' => 'http://austincherry.me'}
  s.source       = { :git => 'https://github.com/daltoniam/Starscream.git',  :tag => '0.9.1'}
  s.platform     = :ios, 8.0
  s.source_files = '*.{h,swift}'
end
