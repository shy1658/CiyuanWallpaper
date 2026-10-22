cmake_minimum_required(VERSION 3.16)
project(ciyuan_image_decode)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()
set(PREBUILT_LIBS ${NATIVERENDER_ROOT_PATH}/../../../libs/${OHOS_ARCH})

include_directories(${NATIVERENDER_ROOT_PATH})
include_directories(${NATIVERENDER_ROOT_PATH}/include)

add_library(image_decode SHARED napi_init.cpp)

target_link_libraries(image_decode PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libimage_source.so
    libpixelmap.so
    ${PREBUILT_LIBS}/libturbojpeg.so
    ${PREBUILT_LIBS}/libavif.so
    ${PREBUILT_LIBS}/libdav1d.so.7
)
