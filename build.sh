#!/bin/bash
# 直接编译 dylib + 打包 rootless deb（不依赖 Theos / dpkg-deb）
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
OUT="$PROJ/build"
NAME="WXFloatBar"
VERSION="2.2.1"

rm -rf "$OUT"; mkdir -p "$OUT"

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
echo "==> SDK: $SDK"

SRC=("$PROJ/floater/WXGlassView.m"
     "$PROJ/floater/WXTabBarStyler.m"
     "$PROJ/floater/WXSettingsController.m"
     "$PROJ/floater/WXPrefs.m"
     "$PROJ/floater/WXInjector.m")

COMMON=(-isysroot "$SDK" -miphoneos-version-min=15.0
        -dynamiclib -fobjc-arc -O2
        -I"$PROJ/floater"
        -framework UIKit -framework QuartzCore
        -framework CoreGraphics -framework Foundation -framework PhotosUI
        -Wno-deprecated-declarations -Wno-nullability-completeness
        -install_name /usr/lib/TweakInject/$NAME.dylib)

for ARCH in arm64 arm64e; do
  echo "==> 编译 $ARCH"
  xcrun -sdk iphoneos clang -arch "$ARCH" "${COMMON[@]}" \
    -o "$OUT/$NAME-$ARCH.dylib" "${SRC[@]}"
done

echo "==> 合并 fat binary"
lipo -create "$OUT/$NAME-arm64.dylib" "$OUT/$NAME-arm64e.dylib" -output "$OUT/$NAME.dylib"
lipo -info "$OUT/$NAME.dylib"

# ad-hoc 签名：arm64e 在真机上需要有效签名才能被注入加载
echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "$OUT/$NAME.dylib" && \
  codesign -dv "$OUT/$NAME.dylib" 2>&1 | head -5 || echo "codesign 跳过"

echo "==> 组织 rootless 包结构"
PKGROOT="$OUT/pkgroot"
EK_DIR="$PKGROOT/var/jb/usr/lib/TweakInject"
MS_DIR="$PKGROOT/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$EK_DIR" "$MS_DIR" "$PKGROOT/DEBIAN"

# 主路径：ElleKit（Dopamine 用这个）
cp "$OUT/$NAME.dylib" "$EK_DIR/"
cp "$PROJ/$NAME.plist" "$EK_DIR/"

# 兼容路径：老 Substrate。dylib 内有重复加载检测，不会出现两条胶囊
cp "$OUT/$NAME.dylib" "$MS_DIR/"
cp "$PROJ/$NAME.plist" "$MS_DIR/"

echo "==> 打包 deb"
python3 "$PROJ/pack_deb.py" "$PKGROOT" "$OUT/${NAME}_${VERSION}_iphoneos-arm64.deb" "$VERSION"

echo
echo "==> 产物"
ls -lh "$OUT/$NAME.dylib" "$OUT"/*.deb
