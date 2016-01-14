Pod::Spec.new do |s|
  s.name         = "Starscream"
  s.version      = "1.0.3"
  s.summary      = "A conforming WebSocket RFC 6455 client library in Swift for iOS and OSX."
  s.homepage     = "https://github.com/daltoniam/Starscream"
  s.license      = 'Apache License, Version 2.0'
  s.author       = {'Dalton Cherry' => 'http://daltoniam.com', 'Austin Cherry' => 'http://austincherry.me'}
  s.source       = { :git => 'https://github.com/daltoniam/Starscream.git',  :tag => "#{s.version}"}
  s.social_media_url = 'http://twitter.com/daltoniam'
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.9'
  s.tvos.deployment_target = '9.0'
  s.source_files = 'Source/*.swift'
  s.requires_arc = 'true'
end
