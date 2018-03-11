#!/bin/sh
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
EOF