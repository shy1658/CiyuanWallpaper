import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@ohos.base';
import { describeError, Logger } from './Logger';

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

  /**
   * 已解析字节的稳定缓存：以「条目 id + 地址」为键。
   * 易变图源（随机图接口，每次请求同地址返回不同图）一张图只请求一次：
   * 网格、详情、保存、收藏列表全部命中同一份字节，保证“所见即所存”。
   * 会话内不主动淘汰，同一条目在会话内无论怎样刷新都复用首次结果。
   */
  private static resolved: Map<string, ArrayBuffer> = new Map();

  /**
   * 在途请求去重：同一地址并发请求只下载一次。
   * 对易变图源尤为关键——网格与详情页若并发请求同一 api.php 地址，
   * 必须共享同一次下载结果，否则会各自拿到不同的随机图，破坏“所见即所存”。
   */
  private static inflight: Map<string, Promise<ArrayBuffer>> = new Map();

  /**
   * 取图片二进制：命中缓存直接返回；否则按候选地址依次尝试（https→http 回退）。
   * 同一地址并发请求通过 inflight 去重，只下载一次（见类字段说明）。
   */
  static async getBytes(url: string): Promise<ArrayBuffer> {
    if (!url || url.length === 0) {
      throw new Error('empty image url');
    }
    const hit = ImageByteCache.cache.get(url);
    if (hit) {
      return hit;
    }
    // 在途去重：并发请求共享同一次下载
    const existing = ImageByteCache.inflight.get(url);
    if (existing) {
      return existing;
    }
    const task: Promise<ArrayBuffer> = (async (): Promise<ArrayBuffer> => {
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
          lastErr = ImageByteCache.toError(e, ImageByteCache.hostOf(u));
          // HTTP 状态码错误（如 http 567 死链、404）与协议无关：https/http 同一台服务器，
          // 换协议重试必然同样失败，直接终止省一次超时等待（死链快速失败）。
          const msg = lastErr.message;
          if (msg.indexOf('http ') === 0) {
            break;
          }
        }
      }
      throw lastErr;
    })();
    ImageByteCache.inflight.set(url, task);
    try {
      return await task;
    } finally {
      ImageByteCache.inflight.delete(url);
    }
  }

  /**
   * 按壁纸条目取字节：在 getBytes 之上，额外以「条目 id + 地址」为键缓存已解析字节。
   * 对易变图源（随机图接口）保证“一张图只请求一次”：网格、详情、保存、收藏列表
   * 全部命中同一份字节，彻底杜绝“预览与保存不是同一张图”的随机错位。
   * id 为空（调用方无条目上下文）时退化为纯 URL 缓存。
   */
  static async getBytesForItem(id: string, url: string): Promise<ArrayBuffer> {
    if (!url || url.length === 0) {
      throw new Error('empty image url');
    }
    const key = (id && id.length > 0) ? `${id}#${url}` : url;
    const resolved = ImageByteCache.resolved.get(key);
    if (resolved) {
      return resolved;
    }
    const buf = await ImageByteCache.getBytes(url);
    ImageByteCache.resolved.set(key, buf);
    return buf;
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
    let buf: ArrayBuffer;
    try {
      buf = await ImageByteCache.downloadOnce(u);
    } catch (e) {
      const code = (e as BusinessError).code;
      if (code === 2300063) {
        // Maximum file size exceeded：切流式接收
        buf = await ImageByteCache.downloadStream(u);
      } else {
        throw ImageByteCache.toError(e, ImageByteCache.hostOf(u));
      }
    }
    return ImageByteCache.deobfuscate(buf);
  }

  /**
   * 图片去混淆：部分图源会把图片的每个字节与一个单字节 key 异或（实测不同响应
   * key 不同：0x54 / 0xA6），系统解码器因此认不出格式，报 "Decode image header failed"。
   *
   * 思路：图片格式的魔数是固定的，可由魔数反推出 key 并自校验——
   * 例如 WebP 文件头恒为 'RIFF'+长度+'WEBP'，共 8 个已知字节；两段各自推导出
   * 同一个 key 即认定命中，随后整块 XOR 还原。仅在原格式无法识别时才尝试，
   * 正常图片零影响。
   */
  private static deobfuscate(buf: ArrayBuffer): ArrayBuffer {
    if (!buf || buf.byteLength < 16) {
      return buf;
    }
    if (ImageByteCache.formatHint(buf) !== 'unknown') {
      return buf; // 格式可识别：未混淆，原样返回
    }
    const b = new Uint8Array(buf);
    // 签名表：[偏移, 期望字节]（RIFF 的 4~7 字节是长度字段，不参与校验）
    const SIGS: number[][][] = [
      [[0, 0x52], [1, 0x49], [2, 0x46], [3, 0x46], [8, 0x57], [9, 0x45], [10, 0x42], [11, 0x50]], // RIFF....WEBP
      [[0, 0xFF], [1, 0xD8], [2, 0xFF]],                                                          // JPEG
      [[0, 0x89], [1, 0x50], [2, 0x4E], [3, 0x47]],                                               // PNG
      [[0, 0x47], [1, 0x49], [2, 0x46], [3, 0x38]],                                               // GIF8
      [[0, 0x42], [1, 0x4D]]                                                                      // BMP
    ];
    for (let s = 0; s < SIGS.length; s++) {
      const sig = SIGS[s];
      let key = -1;
      let match = true;
      for (let i = 0; i < sig.length; i++) {
        const k = (b[sig[i][0]] ^ sig[i][1]) & 0xFF;
        if (key < 0) {
          key = k;
        } else if (k !== key) {
          match = false;
          break;
        }
      }
      if (match && key > 0) {
        // key=0 视为未混淆（异常巧合），跳过。
        // 原地按 4 字节字 XOR：比逐字节循环快约 4 倍，且免去一次大缓冲拷贝
        // （实测 20MB 原图逐字节还原在主线程可感知卡顿，字运算后基本瞬时）。
        const pattern = ((key) | (key << 8) | (key << 16) | (key << 24)) >>> 0;
        const words = Math.floor(b.length / 4);
        const w = new Uint32Array(buf, 0, words);
        for (let i = 0; i < words; i++) {
          w[i] = (w[i] ^ pattern) >>> 0;
        }
        for (let i = words * 4; i < b.length; i++) {
          b[i] = (b[i] ^ key) & 0xFF;
        }
        Logger.i('ImageByteCache', `检测到单字节 XOR 混淆图片（key=0x${key.toString(16)}），已还原 ${buf.byteLength} 字节`);
        return buf;
      }
    }
    return buf;
  }

  /**
   * 把任意捕获到的异常规范化为标准 Error，保证真实错误码（BusinessError.code）
   * 不丢失——否则裸 BusinessError 透传给 Logger.e 时 name/message 均为 undefined，
   * 日志会显示 "undefined: undefined"，无法定位是 2300063 超限、网络错误还是其他。
   * 规范后的 Error.message 形如 "[code 2300063] ... @ image.coolapk.com"，
   * 末尾带上出错主机，方便一眼看出是哪个图床挂了。
   */
  private static toError(e: Object, ctx?: string): Error {
    const detail = describeError(e);
    // 防重复包装：上层 catch 再次调用 toError 时不再重复追加同一主机
    // （此前日志出现 "http 567 @ image.coolapk.com @ image.coolapk.com"）。
    const suffix = ctx && ctx.length > 0 && detail.indexOf(`@ ${ctx}`) < 0 ? ` @ ${ctx}` : '';
    return new Error(`${detail}${suffix}`);
  }

  /** 从 URL 提取主机名（日志上下文用，避免完整 URL 过长） */
  private static hostOf(u?: string): string {
    if (!u || u.length === 0) {
      return '';
    }
    let rest = u;
    if (rest.startsWith('https://')) {
      rest = rest.substring('https://'.length);
    } else if (rest.startsWith('http://')) {
      rest = rest.substring('http://'.length);
    }
    const slash = rest.indexOf('/');
    return slash >= 0 ? rest.substring(0, slash) : rest;
  }

  /** request() 单次下载。maxLimit 仅在 API >= 23 生效（本工程 API 12 忽略此字段，由 2300063 兜底） */
  private static async downloadOnce(u: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.71',
          // 仅声明系统原生支持的常见格式（JPEG/PNG/WebP/GIF/BMP）。
          // 刻意不含 image/avif 与 */* 通配：HarmonyOS API 12 原生解码器不支持 AVIF
          // （AVIF 自 API 26 才支持），若按 Accept 协商出 AVIF 会触发 “Decode image header failed”。
          'Accept': 'image/jpeg,image/png,image/webp,image/gif,image/bmp'
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
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.71',
          // 与 downloadOnce 一致：仅声明系统原生支持格式，规避 AVIF 协商导致的无解码
          'Accept': 'image/jpeg,image/png,image/webp,image/gif,image/bmp'
        },
        // 大文件弱网放宽超时（request() 快路径保持 30s 不变）
        readTimeout: 60000
      };
      request.requestInStream(u, opts, (err: BusinessError, code: number) => {
        if (err) {
          finish(() => reject(ImageByteCache.toError(err, ImageByteCache.hostOf(u))));
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
    return await ImageByteCache.getBytesValidatedForItem('', url);
  }

  /**
   * 带条目上下文的完整性校验版本：与 getBytesForItem 共用「id + 地址」缓存，
   * 截断重试时同步清除已解析缓存，避免重试仍命中坏数据。
   */
  static async getBytesValidatedForItem(id: string, url: string): Promise<ArrayBuffer> {
    const key = (id && id.length > 0) ? `${id}#${url}` : url;
    const first = await ImageByteCache.getBytesForItem(id, url);
    if (ImageByteCache.isComplete(first)) {
      return first;
    }
    // 首份不完整（移动网络截断）：清掉坏数据后重试一次
    ImageByteCache.evict(url);
    ImageByteCache.resolved.delete(key);
    const second = await ImageByteCache.getBytesForItem(id, url);
    if (ImageByteCache.isComplete(second)) {
      return second;
    }
    throw new Error(`图片数据不完整（下载被截断） @ ${ImageByteCache.hostOf(url)}`);
  }

  /**
   * 由字节解码为 PixelMap，长边超过 maxSide 时按 desiredSize 等比缩小解码。
   * 动机：部分二次元长图原图可达 4000px 以上，全尺寸 createPixelMap 在部分
   * GPU 上会因纹理上限直接失败（报“格式不受支持或文件损坏”），
   * 而缩略图（@960w 等处理后缀）尺寸小无此问题。
   * 注意：只影响预览渲染；保存始终使用原始字节，画质不受影响。
   */
  static async toPixelMapScaled(buf: ArrayBuffer, maxSide: number): Promise<image.PixelMap> {
    let source: image.ImageSource;
    try {
      source = image.createImageSource(buf);
    } catch (e) {
      throw ImageByteCache.decodeError(e, buf, 'createImageSource');
    }
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
    try {
      if (width <= 0 || height <= 0 || longSide <= maxSide) {
        return await source.createPixelMap();
      }
      const scale = maxSide / longSide;
      const dw = Math.max(1, Math.round(width * scale));
      const dh = Math.max(1, Math.round(height * scale));
      return await source.createPixelMap({ desiredSize: { width: dw, height: dh } });
    } catch (e) {
      throw ImageByteCache.decodeError(e, buf, 'createPixelMap');
    }
  }

  /** 把解码失败规范化为带“真实格式”的可读错误，便于日志定位（如 AVIF 协商） */
  private static decodeError(e: Object, buf: ArrayBuffer, stage: string): Error {
    const fmt = ImageByteCache.formatHint(buf);
    const detail = describeError(e);
    let hint = '';
    if (fmt === 'avif/heif') {
      hint = '（AVIF/HEIF：API 26 起系统原生解码；若仍失败说明数据损坏或不完整）';
    } else if (fmt === 'unknown') {
      hint = `（字节头无法识别为已知图片格式，可能是 HTML 错误页或加密/损坏数据，前16字节=${ImageByteCache.headHex(buf)}）`;
    }
    return new Error(`图片解码失败[${stage}] 格式=${fmt} ${detail}${hint}`);
  }

  /** 按文件头魔数粗略识别图片格式，识别不出返回 'unknown' */
  private static formatHint(buf: ArrayBuffer): string {
    const b = new Uint8Array(buf);
    const n = b.length;
    if (n >= 3 && b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) {
      return 'jpeg';
    }
    if (n >= 4 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) {
      return 'png';
    }
    if (n >= 4 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
      return 'gif';
    }
    if (n >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      return 'webp';
    }
    if (n >= 2 && b[0] === 0x42 && b[1] === 0x4D) {
      return 'bmp';
    }
    // ISOBMFF：4 字节 box size + 'ftyp'，AVIF/HEIF 均以此开头（API 26 起系统原生解码）
    if (n >= 12 && b[4] === 0x66 && b[5] === 0x74 && b[6] === 0x79 && b[7] === 0x70) {
      return 'avif/heif';
    }
    return 'unknown';
  }

  /** 取前 16 字节的十六进制，用于解码失败日志辅助定位 */
  private static headHex(buf: ArrayBuffer): string {
    const b = new Uint8Array(buf);
    const n = Math.min(16, b.length);
    let s = '';
    for (let i = 0; i < n; i++) {
      s += (b[i] < 16 ? '0' : '') + b[i].toString(16) + (i < n - 1 ? ' ' : '');
    }
    return s || '(空数据)';
  }
}
