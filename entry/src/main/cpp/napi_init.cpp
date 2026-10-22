// 次元壁纸 HarmonyOS 原生解码模块
// 组合拳：
//   1) AVIF      -> libavif + dav1d（API 12 系统原生不支持 AVIF，靠三方库补齐）
//   2) JPEG      -> libjpeg-turbo/turbojpeg（显式处理渐进式 JPEG，避免系统解码器兼容差异）
//   3) 其他格式   -> Image_NativeModule（系统原生解码：PNG/WebP/GIF/BMP/HEIF 等）
//   4) 末级兜底   -> 任何专门解码失败后，再走 Image_NativeModule 一次
// 解码结果统一经 OH_PixelmapNative_ConvertPixelmapNativeToNapi 转成 ArkTS 的 PixelMap。

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include <hilog/log.h>
#include "napi/native_api.h"

#include "multimedia/image_framework/image/image_common.h"
#include "multimedia/image_framework/image/image_source_native.h"
#include "multimedia/image_framework/image/pixelmap_native.h"

#include "turbojpeg.h"
#include "avif/avif.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "CiyuanImgDecode"

#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

namespace {

enum class Fmt { UNKNOWN, AVIF, JPEG, OTHER };

const char* FmtName(Fmt f) {
    switch (f) {
        case Fmt::AVIF: return "avif";
        case Fmt::JPEG: return "jpeg";
        case Fmt::OTHER: return "other";
        default: return "unknown";
    }
}

// 按字节魔数判定格式：AVIF/HEIF 走 ISOBMFF，需在 ftyp 兼容品牌表中找 avif/avis
Fmt DetectFormat(const uint8_t* b, size_t n) {
    if (n >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
        return Fmt::JPEG;
    }
    if (n >= 12 && std::memcmp(b + 4, "ftyp", 4) == 0) {
        uint32_t boxSize = (static_cast<uint32_t>(b[0]) << 24) | (static_cast<uint32_t>(b[1]) << 16) |
                           (static_cast<uint32_t>(b[2]) << 8) | static_cast<uint32_t>(b[3]);
        size_t end = std::min<size_t>(n, std::max<size_t>(boxSize, 16));
        for (size_t i = 8; i + 4 <= end; i += 4) {
            if (std::memcmp(b + i, "avif", 4) == 0 || std::memcmp(b + i, "avis", 4) == 0) {
                return Fmt::AVIF;
            }
        }
    }
    return Fmt::OTHER;
}

// AVIF/HEIF：libavif + dav1d 解码为 RGBA8888
bool DecodeAvif(const uint8_t* data, size_t len, std::vector<uint8_t>& outRgba, uint32_t& outW, uint32_t& outH) {
    avifDecoder* decoder = avifDecoderCreate();
    if (decoder == nullptr) {
        return false;
    }
    // 解码线程数保持克制：壁纸单张解码，过多线程反而抢 CPU
    decoder->maxThreads = 2;

    bool ok = false;
    do {
        if (avifDecoderSetIOMemory(decoder, data, len) != AVIF_RESULT_OK) {
            LOGE("avif: set io memory failed");
            break;
        }
        avifResult r = avifDecoderParse(decoder);
        if (r != AVIF_RESULT_OK) {
            LOGE("avif: parse failed: %{public}s", avifResultToString(r));
            break;
        }
        r = avifDecoderNextImage(decoder);
        if (r != AVIF_RESULT_OK) {
            LOGE("avif: next image failed: %{public}s", avifResultToString(r));
            break;
        }

        avifRGBImage rgb;
        avifRGBImageSetDefaults(&rgb, decoder->image);
        rgb.format = AVIF_RGB_FORMAT_RGBA;
        rgb.depth = 8;
        if (avifRGBImageAllocatePixels(&rgb) != AVIF_RESULT_OK) {
            LOGE("avif: allocate rgb pixels failed");
            break;
        }
        r = avifImageYUVToRGB(decoder->image, &rgb);
        if (r != AVIF_RESULT_OK) {
            LOGE("avif: yuv->rgb failed: %{public}s", avifResultToString(r));
            avifRGBImageFreePixels(&rgb);
            break;
        }

        outW = rgb.width;
        outH = rgb.height;
        const size_t rowBytes = static_cast<size_t>(outW) * 4;
        outRgba.resize(rowBytes * outH);
        // rowBytes 可能带对齐填充，逐行紧凑拷贝，保证后续 CreatePixelmap 的正确步长
        for (uint32_t y = 0; y < outH; ++y) {
            std::memcpy(outRgba.data() + static_cast<size_t>(y) * rowBytes,
                        rgb.pixels + static_cast<size_t>(y) * rgb.rowBytes, rowBytes);
        }
        avifRGBImageFreePixels(&rgb);
        ok = true;
    } while (false);

    avifDecoderDestroy(decoder);
    return ok;
}

// JPEG（基线/渐进式均支持）：libjpeg-turbo 解码为 RGBA8888
bool DecodeJpeg(const uint8_t* data, size_t len, std::vector<uint8_t>& outRgba, uint32_t& outW, uint32_t& outH) {
    tjhandle handle = tjInitDecompress();
    if (handle == nullptr) {
        return false;
    }
    int width = 0;
    int height = 0;
    int subsamp = 0;
    int colorspace = 0;
    bool ok = false;
    do {
        if (tjDecompressHeader3(handle, data, static_cast<unsigned long>(len), &width, &height, &subsamp, &colorspace) != 0) {
            LOGE("jpeg: header failed: %{public}s", tjGetErrorStr2(handle));
            break;
        }
        if (width <= 0 || height <= 0) {
            break;
        }
        outRgba.resize(static_cast<size_t>(width) * static_cast<size_t>(height) * 4);
        if (tjDecompress2(handle, data, static_cast<unsigned long>(len), outRgba.data(), width, 0, height,
                          TJPF_RGBA, TJFLAG_FASTDCT) != 0) {
            LOGE("jpeg: decompress failed: %{public}s", tjGetErrorStr2(handle));
            break;
        }
        outW = static_cast<uint32_t>(width);
        outH = static_cast<uint32_t>(height);
        ok = true;
    } while (false);
    tjDestroy(handle);
    return ok;
}

// 系统原生解码（Image_NativeModule）。
// 注意 API 12 的部分格式（如 WebP）不支持在 CreatePixelmap 时按 desiredSize 缩放，
// 会直接返回错误；因此带 desiredSize 失败后，必须再去掉 options 全尺寸解码，
// 最后用 OH_PixelmapNative_Scale 缩放，否则会误判为“core decode failed”。
OH_PixelmapNative* DecodeCore(const uint8_t* data, size_t len, uint32_t maxSide, std::string& reason) {
    OH_ImageSourceNative* source = nullptr;
    Image_ErrorCode ec = OH_ImageSourceNative_CreateFromData(const_cast<uint8_t*>(data), len, &source);
    if (ec != IMAGE_SUCCESS || source == nullptr) {
        LOGE("core: create source failed: %{public}d", static_cast<int>(ec));
        reason = "core source ec=" + std::to_string(static_cast<int>(ec));
        return nullptr;
    }

    uint32_t width = 0;
    uint32_t height = 0;
    OH_ImageSource_Info* info = nullptr;
    if (OH_ImageSourceInfo_Create(&info) == IMAGE_SUCCESS && info != nullptr) {
        if (OH_ImageSourceNative_GetImageInfo(source, 0, info) == IMAGE_SUCCESS) {
            OH_ImageSourceInfo_GetWidth(info, &width);
            OH_ImageSourceInfo_GetHeight(info, &height);
        }
        OH_ImageSourceInfo_Release(info);
    }

    const uint32_t longSide = std::max(width, height);
    const bool wantScale = (width > 0 && height > 0 && maxSide > 0 && longSide > maxSide);

    // 第一次尝试：带 desiredSize（大图首选，省内存）
    if (wantScale) {
        OH_DecodingOptions* options = nullptr;
        if (OH_DecodingOptions_Create(&options) == IMAGE_SUCCESS && options != nullptr) {
            double ratio = static_cast<double>(maxSide) / static_cast<double>(longSide);
            Image_Size desired;
            desired.width = std::max<uint32_t>(1, static_cast<uint32_t>(width * ratio));
            desired.height = std::max<uint32_t>(1, static_cast<uint32_t>(height * ratio));
            OH_DecodingOptions_SetDesiredSize(options, &desired);

            OH_PixelmapNative* pixelmap = nullptr;
            ec = OH_ImageSourceNative_CreatePixelmap(source, options, &pixelmap);
            OH_DecodingOptions_Release(options);
            if (ec == IMAGE_SUCCESS && pixelmap != nullptr) {
                OH_ImageSourceNative_Release(source);
                return pixelmap;
            }
            LOGE("core: create pixelmap with desiredSize failed: %{public}d, retry full size",
                 static_cast<int>(ec));
        }
    }

    // 第二次尝试：不带缩放参数全尺寸解码，再按长边缩放
    OH_DecodingOptions* plainOptions = nullptr;
    if (OH_DecodingOptions_Create(&plainOptions) != IMAGE_SUCCESS || plainOptions == nullptr) {
        OH_ImageSourceNative_Release(source);
        reason = "core options create failed";
        return nullptr;
    }
    OH_PixelmapNative* pixelmap = nullptr;
    ec = OH_ImageSourceNative_CreatePixelmap(source, plainOptions, &pixelmap);
    OH_DecodingOptions_Release(plainOptions);
    OH_ImageSourceNative_Release(source);

    if (ec != IMAGE_SUCCESS || pixelmap == nullptr) {
        LOGE("core: create pixelmap failed: %{public}d", static_cast<int>(ec));
        reason = "core pixelmap ec=" + std::to_string(static_cast<int>(ec));
        return nullptr;
    }
    if (wantScale) {
        float scale = static_cast<float>(maxSide) / static_cast<float>(longSide);
        OH_PixelmapNative_Scale(pixelmap, scale, scale);
    }
    return pixelmap;
}

// RGBA8888 裸数据 -> PixelMap，并按 maxSide 等比缩放（大图保护）
OH_PixelmapNative* CreateRgbaPixelMap(std::vector<uint8_t>& rgba, uint32_t width, uint32_t height, uint32_t maxSide) {
    if (rgba.empty() || width == 0 || height == 0) {
        return nullptr;
    }
    OH_Pixelmap_InitializationOptions* options = nullptr;
    if (OH_PixelmapInitializationOptions_Create(&options) != IMAGE_SUCCESS || options == nullptr) {
        return nullptr;
    }
    OH_PixelmapInitializationOptions_SetWidth(options, width);
    OH_PixelmapInitializationOptions_SetHeight(options, height);
    OH_PixelmapInitializationOptions_SetPixelFormat(options, PIXEL_FORMAT_RGBA_8888);
    OH_PixelmapInitializationOptions_SetAlphaType(options, PIXELMAP_ALPHA_TYPE_OPAQUE);

    OH_PixelmapNative* pixelmap = nullptr;
    Image_ErrorCode ec = OH_PixelmapNative_CreatePixelmap(rgba.data(), rgba.size(), options, &pixelmap);
    OH_PixelmapInitializationOptions_Release(options);
    if (ec != IMAGE_SUCCESS || pixelmap == nullptr) {
        LOGE("rgba: create pixelmap failed: %{public}d", static_cast<int>(ec));
        return nullptr;
    }

    uint32_t longSide = std::max(width, height);
    if (maxSide > 0 && longSide > maxSide) {
        float scale = static_cast<float>(maxSide) / static_cast<float>(longSide);
        OH_PixelmapNative_Scale(pixelmap, scale, scale);
    }
    return pixelmap;
}

OH_PixelmapNative* DecodeToPixelMap(const uint8_t* data, size_t len, uint32_t maxSide, std::string& reason) {
    Fmt fmt = DetectFormat(data, len);
    LOGI("decode: format=%{public}s bytes=%{public}zu maxSide=%{public}u", FmtName(fmt), len, maxSide);

    if (fmt == Fmt::AVIF) {
        std::vector<uint8_t> rgba;
        uint32_t w = 0;
        uint32_t h = 0;
        if (DecodeAvif(data, len, rgba, w, h)) {
            OH_PixelmapNative* pm = CreateRgbaPixelMap(rgba, w, h, maxSide);
            if (pm != nullptr) {
                return pm;
            }
        }
        reason = "avif decode failed";
    }

    if (fmt == Fmt::JPEG) {
        std::vector<uint8_t> rgba;
        uint32_t w = 0;
        uint32_t h = 0;
        if (DecodeJpeg(data, len, rgba, w, h)) {
            OH_PixelmapNative* pm = CreateRgbaPixelMap(rgba, w, h, maxSide);
            if (pm != nullptr) {
                return pm;
            }
        }
        if (reason.empty()) {
            reason = "jpeg decode failed";
        }
    }

    // 其余格式 & 专门解码失败后的末级兜底：系统原生解码
    std::string coreReason;
    OH_PixelmapNative* pm = DecodeCore(data, len, maxSide, coreReason);
    if (pm != nullptr) {
        return pm;
    }
    if (reason.empty()) {
        reason = coreReason.empty() ? "core decode failed" : coreReason;
    } else if (!coreReason.empty()) {
        // 保留专门解码器的失败原因，同时附上系统兜底的错误码，便于一次定位
        reason += " / " + coreReason;
    }
    return nullptr;
}

struct DecodeWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<uint8_t> data;
    uint32_t maxSide = 0;
    OH_PixelmapNative* pixelmap = nullptr;
    std::string reason;
};

// 工作线程：只做纯解码，不接触 napi
void ExecuteDecode(napi_env env, void* data) {
    auto* work = static_cast<DecodeWork*>(data);
    work->pixelmap = DecodeToPixelMap(work->data.data(), work->data.size(), work->maxSide, work->reason);
}

// 主线程：把原生 PixelMap 转成 napi 对象并 resolve / reject
void CompleteDecode(napi_env env, napi_status status, void* data) {
    auto* work = static_cast<DecodeWork*>(data);
    napi_value message = nullptr;
    napi_value error = nullptr;

    if (work->pixelmap != nullptr) {
        napi_value pixelmapValue = nullptr;
        Image_ErrorCode ec = OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, work->pixelmap, &pixelmapValue);
        if (ec == IMAGE_SUCCESS && pixelmapValue != nullptr) {
            // 转换成功后所有权已转交给 napi 包装对象，不能再手动 Release
            napi_resolve_deferred(env, work->deferred, pixelmapValue);
            napi_delete_async_work(env, work->work);
            delete work;
            return;
        }
        OH_PixelmapNative_Release(work->pixelmap);
        napi_create_string_utf8(env, "convert pixelmap to napi failed", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
    } else {
        if (work->reason.empty()) {
            work->reason = "decode failed";
        }
        LOGE("decode failed: %{public}s", work->reason.c_str());
        napi_create_string_utf8(env, work->reason.c_str(), NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
    }
    napi_reject_deferred(env, work->deferred, error);
    napi_delete_async_work(env, work->work);
    delete work;
}

napi_value DecodePixelMap(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    // 参数不合法时仍返回 Promise，用 reject 表达错误（避免调用方 try/catch 语义分裂）
    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);
    auto reject = [&](const char* msg) -> napi_value {
        napi_value message = nullptr;
        napi_value error = nullptr;
        napi_create_string_utf8(env, msg, NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, deferred, error);
        return promise;
    };

    if (argc < 1 || args[0] == nullptr) {
        return reject("missing image buffer");
    }
    napi_valuetype type = napi_undefined;
    napi_typeof(env, args[0], &type);
    if (type != napi_object) {
        return reject("image buffer must be ArrayBuffer");
    }

    void* raw = nullptr;
    size_t length = 0;
    if (napi_get_arraybuffer_info(env, args[0], &raw, &length) != napi_ok || raw == nullptr || length == 0) {
        return reject("invalid ArrayBuffer");
    }

    uint32_t maxSide = 0;
    if (argc >= 2 && args[1] != nullptr) {
        int32_t value = 0;
        if (napi_get_value_int32(env, args[1], &value) == napi_ok && value > 0) {
            maxSide = static_cast<uint32_t>(value);
        }
    }

    auto* work = new DecodeWork();
    work->deferred = deferred;
    work->maxSide = maxSide;
    // 拷贝一份：调用返回后原始 ArrayBuffer 可能被回收
    const uint8_t* begin = static_cast<const uint8_t*>(raw);
    work->data.assign(begin, begin + length);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "decodePixelMap", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteDecode, CompleteDecode, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"decodePixelMap", nullptr, DecodePixelMap, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

static napi_module g_imageDecodeModule = {
    1,                       // nm_version
    0,                       // nm_flags
    nullptr,                 // nm_filename
    Init,                    // nm_register_func
    "image_decode",          // nm_modname
    nullptr,                 // nm_priv
    {0},                     // reserved
};

extern "C" __attribute__((constructor)) void RegisterImageDecodeModule(void) {
    napi_module_register(&g_imageDecodeModule);
}
