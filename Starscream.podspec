Pod::Spec.new do |s|
  s.name         = "Starscream"
  s.version      = "3.0.4"
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
  s.source_files = 'Sources/*.swift'
  s.libraries    = 'z'
  s.pod_target_xcconfig = {
  'SWIFT_VERSION' => '4.0',
  'SWIFT_INCLUDE_PATHS' => '${BUILT_PRODUCTS_DIR}/StarscreamModuleMap'
  }
  s.script_phase = {
  :name => 'Generate Module Map',
  :script => '
if [ -d "${BUILT_PRODUCTS_DIR}/StarscreamModuleMap" ]; then
echo "${BUILT_PRODUCTS_DIR}/StarscreamModuleMap directory already exists, so skipping the rest of the script."
exit 0
fi

mkdir -p "${BUILT_PRODUCTS_DIR}/StarscreamModuleMap"
cat <<EOF > "${BUILT_PRODUCTS_DIR}/StarscreamModuleMap/module.modulemap"
module SSCZLib [system] {
    header "${SDK_DIR}/usr/include/zlib.h"
    link "z"
    export *
}
module SSCommonCrypto [system] {
    header "${SDK_DIR}/usr/include/CommonCrypto/CommonCrypto.h"
    export *
}
EOF',
  :execution_position => :before_compile
  }
end
