Pod::Spec.new do |s|
  s.name         = "Starscream"
  s.version      = "3.0.5"
  s.summary      = "A conforming WebSocket RFC 6455 client library in Swift."
  s.homepage     = "https://github.com/daltoniam/Starscream"
  s.license      = 'Apache License, Version 2.0'
  s.author       = {'Dalton Cherry' => 'http://daltoniam.com', 'Austin Cherry' => 'http://austincherry.me'}
  s.source       = { :git => 'https://github.com/daltoniam/Starscream.git',  :tag => "#{s.version}"}
  s.social_media_url = 'http://twitter.com/daltoniam'
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'
  s.tvos.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'
  s.source_files = 'Sources/**/*.{h,m,swift}'
  s.module_map = 'Sources/modulemap/Starscream.modulemap'
  s.private_header_files = 'Sources/modulemap/**/*.h'
  s.pod_target_xcconfig = {
  'SWIFT_VERSION' => '4.1'
  }
end
