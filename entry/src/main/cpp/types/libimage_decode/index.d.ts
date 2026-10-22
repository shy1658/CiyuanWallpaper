import { image } from '@kit.ImageKit';

/**
 * 原生解码入口（AVIF -> libavif/dav1d；JPEG -> libjpeg-turbo；其他 -> Image_NativeModule）。
 * @param buf 图片原始字节
 * @param maxSide 长边上限（0 表示不缩放）
 */
export const decodePixelMap: (buf: ArrayBuffer, maxSide: number) => Promise<image.PixelMap>;
