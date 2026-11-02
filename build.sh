#!/bin/bash
# 直接编译 dylib + 打包 rootless deb（不依赖 Theos / dpkg-deb）
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ/build"
NAME="WXFloatBar"
VERSION="1.0.0"

rm -rf "$OUT"; mkdir -p "$OUT"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "==> SDK: $SDK"

SRC=("$PROJ/floater/WXGlassView.m"
     "$PROJ/floater/WXFloatBarManager.m"
     "$PROJ/floater/WXInjector.m")

COMMON=(-isysroot "$SDK" -miphoneos-version-min=15.0
        -dynamiclib -fobjc-arc -O2
        -I"$PROJ/floater"
        -framework UIKit -framework QuartzCore
        -framework CoreGraphics -framework Foundation
        -Wno-deprecated-declarations -Wno-nullability-completeness
        -install_name /Library/MobileSubstrate/DynamicLibraries/$NAME.dylib)

for ARCH in arm64 arm64e; do
  echo "==> 编译 $ARCH"
  xcrun -sdk iphoneos clang -arch "$ARCH" "${COMMON[@]}" \
    -o "$OUT/$NAME-$ARCH.dylib" "${SRC[@]}"
done

echo "==> 合并 fat binary"
lipo -create "$OUT/$NAME-arm64.dylib" "$OUT/$NAME-arm64e.dylib" -output "$OUT/$NAME.dylib"
lipo -info "$OUT/$NAME.dylib"

echo "==> 组织 rootless 包结构"
PKGROOT="$OUT/pkgroot"
LIBDIR="$PKGROOT/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$LIBDIR" "$PKGROOT/DEBIAN"
cp "$OUT/$NAME.dylib" "$LIBDIR/"
cp "$PROJ/$NAME.plist" "$LIBDIR/"

echo "==> 打包 deb"
python3 "$PROJ/pack_deb.py" "$PKGROOT" "$OUT/${NAME}_${VERSION}_iphoneos-arm64.deb" "$VERSION"

echo
echo "==> 产物"
ls -lh "$OUT/$NAME.dylib" "$OUT"/*.deb
