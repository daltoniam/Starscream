#!/bin/sh
mkdir -p "${MODULE_CACHE_DIR}/StarscreamModuleMap"
cat <<EOF > "${MODULE_CACHE_DIR}/StarscreamModuleMap/module.modulemap"
module SSCZLib [system] {
    header "${SDK_DIR}/usr/include/zlib.h"
    link "z"
    export *
}
module SSCommonCrypto [system] {
    header "${SDK_DIR}/usr/include/CommonCrypto/CommonCrypto.h"
    export *
}
EOF