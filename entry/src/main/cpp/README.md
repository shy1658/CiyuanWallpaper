# 原生解码模块（libimage_decode.so）

API 12 的系统 ImageKit 不支持 AVIF，且不同系统版本对渐进式 JPEG 的兼容性存在差异。
本模块用「组合拳」把解码能力补齐，并通过 NAPI 异步工作线程返回 `image.PixelMap`：

| 格式 | 解码器 | 说明 |
|---|---|---|
| AVIF / HEIF | **libavif + dav1d** | API 12 系统原生不支持，必须三方库补齐 |
| JPEG（基线 / 渐进式） | **libjpeg-turbo (turbojpeg)** | 显式处理渐进式，绕开系统解码器差异 |
| PNG / WebP / GIF / BMP | **Image_NativeModule** | 系统原生解码（`OH_ImageSourceNative_*`） |
| 任意失败 | Image_NativeModule 末级兜底 | 保证不因专门解码器异常而整体失败 |

ArkTS 侧 `ImageByteCache.toPixelMapScaled()` 优先调用本模块；若原生库加载或解码失败，
自动回退到 `@kit.ImageKit`，任何机型都不会白屏。

## 目录

```
cpp/
├── CMakeLists.txt          # 链接系统库 + 预编译三方库
├── napi_init.cpp           # NAPI 入口 + 格式分发 + 异步解码
├── include/                # avif / turbojpeg 头文件
└── types/libimage_decode/  # ArkTS 类型声明（.d.ts）

entry/libs/arm64-v8a/       # 预编译三方库（随 HAP 打包）
├── libavif.so
├── libturbojpeg.so
└── libdav1d.so.7
```

## 三方库交叉编译（OHOS clang-15 / arm64）

工具链文件关键项：

```cmake
set(CMAKE_SYSTEM_NAME OHOS)
set(CMAKE_C_COMPILER   .../native/llvm/bin/aarch64-unknown-linux-ohos-clang)
set(CMAKE_CXX_COMPILER .../native/llvm/bin/aarch64-unknown-linux-ohos-clang++)
set(CMAKE_SYSROOT      .../native/sysroot)
```

```bash
# 1) libjpeg-turbo（关闭 SIMD 汇编，避免交叉汇编器差异）
cmake -S libjpeg-turbo -B build-jpeg \
  -DCMAKE_TOOLCHAIN_FILE=ohos-aarch64.toolchain.cmake \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DWITH_SIMD=0 -DENABLE_SHARED=1 -DENABLE_STATIC=0 -DWITH_TURBOJPEG=1
cmake --build build-jpeg -j && cmake --install build-jpeg

# 2) dav1d（meson，关闭汇编）
meson setup build-dav1d dav1d --cross-file=ohos-aarch64.meson.ini \
  --prefix=$PREFIX --default-library=shared \
  -Denable_asm=false -Denable_tools=false -Denable_tests=false -Denable_examples=false
ninja -C build-dav1d && ninja -C build-dav1d install

# 3) libavif（dav1d 作为 AV1 解码后端）
cmake -S libavif -B build-avif \
  -DCMAKE_TOOLCHAIN_FILE=ohos-aarch64.toolchain.cmake \
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DBUILD_SHARED_LIBS=ON \
  -DAVIF_CODEC_DAV1D=SYSTEM \
  -DDAV1D_INCLUDE_DIR=$PREFIX/include -DDAV1D_LIBRARY=$PREFIX/lib/libdav1d.so \
  -DAVIF_LIBYUV=OFF -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF
cmake --build build-avif -j && cmake --install build-avif
```

产物按 SONAME 放入 `entry/libs/arm64-v8a/`（`libdav1d.so.7` 必须保持该文件名，
因为 `libavif.so` 的 `DT_NEEDED` 指向 `libdav1d.so.7`）。

## 构建

```bash
bash build.sh
# 产物：entry/build/default/outputs/default/entry-default-signed.hap
```
