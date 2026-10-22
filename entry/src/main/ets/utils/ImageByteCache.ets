import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@ohos.base';

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
        lastErr = ImageByteCache.toError(e);
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

  /**
   * 实际下载：带浏览器 UA 与 Accept，避免个别图床按 UA 拦截。
   *
   * 两段式路径：
   * 1. request() 快路径：适用于绝大多数图片（缩略图与 5MB 以内原图）；
   * 2. 若响应体超过 request() 的接收上限（API < 23 为 5MB，错误码 2300063），
   *    自动切 requestInStream 流式重试——API < 23 上即使调大 maxLimit 也无效，
   *    流式是官方唯一能突破 5MB 的方案（本工程 API 12，>5MB 原图靠它救回）。
   */
  private static async download(u: string): Promise<ArrayBuffer> {
    try {
      return await ImageByteCache.downloadOnce(u);
    } catch (e) {
      const code = (e as BusinessError).code;
      if (code === 2300063) {
        // Maximum file size exceeded：切流式接收
        return await ImageByteCache.downloadStream(u);
      }
      throw ImageByteCache.toError(e);
    }
  }

  /**
   * 把任意捕获到的异常规范化为标准 Error，保证真实错误码（BusinessError.code）
   * 不丢失——否则裸 BusinessError 透传给 Logger.e 时 name/message 均为 undefined，
   * 日志会显示 "undefined: undefined"，无法定位是 2300063 超限、网络错误还是其他。
   * 规范后的 Error.message 形如 "[code 2300063] ..."，Logger 也会单独打印 code=。
   */
  private static toError(e: Object): Error {
    const anyErr = e as BusinessError;
    const code = anyErr?.code;
    const emsg = anyErr?.message ?? anyErr?.name;
    if (code !== undefined && code !== null) {
      return new Error(`[code ${code}] ${emsg ?? '(无 message)'}`);
    }
    if (emsg !== undefined && emsg.length > 0) {
      return new Error(emsg);
    }
    return new Error(String(e));
  }

  /** request() 单次下载。maxLimit 仅在 API >= 23 生效（本工程 API 12 忽略此字段，由 2300063 兜底） */
  private static async downloadOnce(u: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.65',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        // API >= 23 时显式放行 64MB（默认仅 5MB）；API < 23 无效，超限走流式
        maxLimit: ImageByteCache.MAX_IMAGE_BYTES,
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

  /** 流式接收安全上限：防止异常响应把内存撑爆（正常原图远小于此值） */
  private static readonly MAX_STREAM_BYTES: number = 128 * 1024 * 1024;

  /** request() 快路径的显式接收上限（API >= 23 生效，见 downloadOnce） */
  private static readonly MAX_IMAGE_BYTES: number = 64 * 1024 * 1024;

  /**
   * 流式下载：requestInStream 发起请求，dataReceive 分片累积，dataEnd 收尾拼接。
   * 无 5MB 接收上限，用于 >5MB 的大原图（实测 >10MB 长图必经此路）。
   */
  private static downloadStream(u: string): Promise<ArrayBuffer> {
    return new Promise<ArrayBuffer>((resolve, reject) => {
      const request = http.createHttp();
      const chunks: ArrayBuffer[] = [];
      let total = 0;
      let settled = false;
      const finish = (fn: () => void) => {
        if (settled) {
          return;
        }
        settled = true;
        request.off('headersReceive');
        request.off('dataReceive');
        request.off('dataEnd');
        request.destroy();
        fn();
      };
      // 响应头事件：无需解析 Content-Length，数据统一走 dataReceive/dataEnd
      request.on('headersReceive', () => {});
      request.on('dataReceive', (data: ArrayBuffer) => {
        chunks.push(data);
        total += data.byteLength;
        if (total > ImageByteCache.MAX_STREAM_BYTES) {
          finish(() => reject(new Error('image too large')));
        }
      });
      request.on('dataEnd', () => {
        finish(() => {
          const merged = new ArrayBuffer(total);
          const view = new Uint8Array(merged);
          let offset = 0;
          for (const c of chunks) {
            view.set(new Uint8Array(c), offset);
            offset += c.byteLength;
          }
          resolve(merged);
        });
      });
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.65',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
        },
        // 大文件弱网放宽超时（request() 快路径保持 30s 不变）
        readTimeout: 60000
      };
      request.requestInStream(u, opts, (err: BusinessError, code: number) => {
        if (err) {
          finish(() => reject(ImageByteCache.toError(err)));
        } else if (code !== 200) {
          finish(() => reject(new Error(`http ${code}`)));
        }
        // code === 200：等待 dataEnd 事件收尾
      });
    });
  }

  /** 由字节解码为 PixelMap（供 ArkUI 直接渲染，所见即所存）。
   * 长边超过 4096 时自动缩小解码，避免超大图超出 GPU 纹理上限导致解码失败。 */
  static async toPixelMap(buf: ArrayBuffer): Promise<image.PixelMap> {
    return await ImageByteCache.toPixelMapScaled(buf, 4096);
  }

  /**
   * 校验下载字节是否完整（按文件头声明的长度判断，主要用于发现传输截断）。
   * HTTP 200 不代表数据完整：移动网络下大图可能只收到一部分仍返回成功，
   * 这种残缺字节解码会失败，若直接保存就是“坏图”。
   */
  static isComplete(buf: ArrayBuffer): boolean {
    if (!buf || buf.byteLength < 12) {
      return false;
    }
    const b = new Uint8Array(buf);
    const n = buf.byteLength;
    // WEBP：'RIFF' + 4 字节小端文件长度（不含前 8 字节）+ 'WEBP'
    if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      const riffSize = (b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24)) >>> 0;
      return riffSize + 8 <= n;
    }
    // JPEG：以 FF D9 结束
    if (b[0] === 0xFF && b[1] === 0xD8) {
      return b[n - 2] === 0xFF && b[n - 1] === 0xD9;
    }
    // PNG：末尾 12 字节内应出现 'IEND' 块标识
    if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) {
      for (let i = n - 12; i <= n - 4; i++) {
        if (i >= 0 && b[i] === 0x49 && b[i + 1] === 0x45 && b[i + 2] === 0x4E && b[i + 3] === 0x44) {
          return true;
        }
      }
      return false;
    }
    // GIF：以 0x3B 结束
    if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) {
      return b[n - 1] === 0x3B;
    }
    // 其他格式：交给解码器判断
    return true;
  }

  /** 清除某个地址及其候选地址的缓存（重试下载前清掉坏数据） */
  private static evict(url: string): void {
    ImageByteCache.cache.delete(url);
    for (const u of ImageByteCache.candidates(url)) {
      ImageByteCache.cache.delete(u);
    }
  }

  /**
   * 取图片二进制并校验完整性：发现截断则清缓存重试一次，仍不完整则抛错。
   * 调用方应把它当作“可用于保存的字节”，未通过校验的数据绝不落盘。
   */
  static async getBytesValidated(url: string): Promise<ArrayBuffer> {
    const first = await ImageByteCache.getBytes(url);
    if (ImageByteCache.isComplete(first)) {
      return first;
    }
    ImageByteCache.evict(url);
    const second = await ImageByteCache.getBytes(url);
    if (ImageByteCache.isComplete(second)) {
      return second;
    }
    throw new Error('图片数据不完整（下载被截断）');
  }

  /**
   * 由字节解码为 PixelMap，长边超过 maxSide 时按 desiredSize 等比缩小解码。
   * 动机：部分二次元长图原图可达 4000px 以上，全尺寸 createPixelMap 在部分
   * GPU 上会因纹理上限直接失败（报“格式不受支持或文件损坏”），
   * 而缩略图（@960w 等处理后缀）尺寸小无此问题。
   * 注意：只影响预览渲染；保存始终使用原始字节，画质不受影响。
   */
  static async toPixelMapScaled(buf: ArrayBuffer, maxSide: number): Promise<image.PixelMap> {
    const source = image.createImageSource(buf);
    let width = 0;
    let height = 0;
    try {
      const info = await source.getImageInfo();
      width = info.size.width;
      height = info.size.height;
    } catch (e) {
      // 取不到尺寸信息：按原尺寸解码
    }
    const longSide = Math.max(width, height);
    if (width <= 0 || height <= 0 || longSide <= maxSide) {
      return await source.createPixelMap();
    }
    const scale = maxSide / longSide;
    const dw = Math.max(1, Math.round(width * scale));
    const dh = Math.max(1, Math.round(height * scale));
    return await source.createPixelMap({ desiredSize: { width: dw, height: dh } });
  }
}
