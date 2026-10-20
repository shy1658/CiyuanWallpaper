import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';

/**
 * 图片字节缓存与加载。
 *
 * 为什么统一走 http 模块字节路径（而不是 ArkUI Image(URL) 组件）：
 * - 应用的账号/列表接口（api.awsl.13th.tech）已证明 http 模块在本机网络可用；
 * - 图片直链（如 B 站图床 i0.hdslb.com）同样用 http 模块拉取，行为一致、可控；
 * - 下载字节后解码为 PixelMap 渲染，可实现 https→http 回退、自定义 UA，
 *   并让“缩略图 / 详情大图 / 保存”复用同一份字节，保证所见即所存。
 *
 * 缓存以原始 URL 为键；对“易变”图源（随机图接口，每次请求同 URL 返回不同图），
 * 网格与详情页用同一 URL 取缓存，从而保证是同一张图。
 */
export class ImageByteCache {
  private static cache: Map<string, ArrayBuffer> = new Map();

  /** 取图片二进制：命中缓存直接返回；否则按候选地址依次尝试（https→http 回退） */
  static async getBytes(url: string): Promise<ArrayBuffer> {
    if (!url || url.length === 0) {
      throw new Error('empty image url');
    }
    const hit = ImageByteCache.cache.get(url);
    if (hit) {
      return hit;
    }
    const candidates = ImageByteCache.candidates(url);
    let lastErr: Error = new Error('image download failed');
    for (const u of candidates) {
      const cached = ImageByteCache.cache.get(u);
      if (cached) {
        ImageByteCache.cache.set(url, cached);
        return cached;
      }
      try {
        const buf = await ImageByteCache.download(u);
        ImageByteCache.cache.set(u, buf);
        ImageByteCache.cache.set(url, buf);
        return buf;
      } catch (e) {
        lastErr = e as Error;
      }
    }
    throw lastErr;
  }

  /** 候选地址：优先尝试 https（无需明文许可），再回退另一协议 */
  private static candidates(url: string): string[] {
    const list: string[] = [];
    if (url.startsWith('http://')) {
      list.push('https://' + url.substring('http://'.length));
      list.push(url);
    } else {
      list.push(url);
      if (url.startsWith('https://')) {
        list.push('http://' + url.substring('https://'.length));
      }
    }
    return list;
  }

  /** 实际下载：带浏览器 UA 与 Accept，避免个别图床按 UA 拦截 */
  private static async download(u: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.5',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 30000
      };
      const resp = await request.request(u, opts);
      if (resp.responseCode !== 200) {
        throw new Error(`http ${resp.responseCode}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      request.destroy();
    }
  }

  /** 由字节解码为 PixelMap（供 ArkUI 直接渲染，所见即所存） */
  static async toPixelMap(buf: ArrayBuffer): Promise<image.PixelMap> {
    const source = image.createImageSource(buf);
    return await source.createPixelMap();
  }
}
