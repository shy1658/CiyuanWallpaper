import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { WallpaperItem } from '../model/WallpaperItem';
import { ImageByteCache } from './ImageByteCache';

/**
 * 壁纸下载与保存工具。
 *
 * 「存到本地」走 DocumentViewPicker 的 DOWNLOAD 模式：跳过选择界面，
 * 自动落盘到 Download/<包名>/ 独立目录，返回具备持久权限的目录 URI。
 * （图库保存功能已移除，统一仅保留本地保存。）
 */
export class ImageSaveUtil {
  /** 已知图片扩展名白名单：仅这些才允许采信 URL 后缀，避免 .php/.asp 等伪后缀 */
  private static readonly KNOWN_IMAGE_EXT: string[] = [
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff'
  ];

  /**
   * 保存文件名：ciyuan_<id>_<时间戳>.<扩展名>。
   * 优先按字节内容（真实图片格式）识别扩展名，无视 URL 后缀（如 .php）。
   */
  static fileNameFor(item: WallpaperItem, buffer?: ArrayBuffer): string {
    return `ciyuan_${item.id}_${Date.now()}.${ImageSaveUtil.extensionFor(item, buffer)}`;
  }

  /**
   * 推断图片扩展名（优先级：字节魔数 > URL 已知图片后缀 > 兜底 jpg）：
   * 1) 传入 buffer 且魔数可识别 → 用真实格式（最可靠，处理 .php/.asp/无后缀接口）；
   * 2) 否则用 URL 后缀，但仅当它属于 KNOWN_IMAGE_EXT 才采信；
   * 3) 兜底默认 jpg（绝不会是 php）。
   */
  static extensionFor(item: WallpaperItem, buffer?: ArrayBuffer): string {
    if (buffer && buffer.byteLength >= 3) {
      const ext = ImageSaveUtil.extensionFromBytes(buffer);
      if (ext.length > 0) {
        return ext;
      }
    }
    const src = item.url && item.url.length > 0 ? item.url : item.thumbUrl;
    if (src && src.length > 0) {
      const m = /\.([a-zA-Z0-9]{2,5})(?:[@?]|$)/.exec(src);
      if (m && m[1] && ImageSaveUtil.KNOWN_IMAGE_EXT.indexOf(m[1].toLowerCase()) >= 0) {
        return m[1].toLowerCase();
      }
    }
    return 'jpg';
  }

  /** 按文件头魔数识别图片格式，识别不出返回空串 */
  static extensionFromBytes(buf: ArrayBuffer): string {
    const b = new Uint8Array(buf);
    const n = b.length;
    // JPEG: FF D8 FF
    if (n >= 3 && b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) {
      return 'jpg';
    }
    // PNG: 89 50 4E 47
    if (n >= 4 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) {
      return 'png';
    }
    // GIF: 47 49 46 38 (GIF8)
    if (n >= 4 && b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) {
      return 'gif';
    }
    // WEBP: RIFF....WEBP
    if (n >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) {
      return 'webp';
    }
    // BMP: 42 4D
    if (n >= 2 && b[0] === 0x42 && b[1] === 0x4D) {
      return 'bmp';
    }
    // TIFF: II*\0 或 MM\0*
    if (n >= 4 && ((b[0] === 0x49 && b[1] === 0x49 && b[2] === 0x2A && b[3] === 0x00) ||
      (b[0] === 0x4D && b[1] === 0x4D && b[2] === 0x00 && b[3] === 0x2A))) {
      return 'tif';
    }
    return '';
  }

  /**
   * 下载图片二进制（网络图）或读取本地预置资源。
   * 网络图统一走字节缓存：原图优先、缩略图兜底（http 模块 + https→http 回退），
   * 与详情页预览/保存链路一致，保证原图不可达时保存不失败。
   */
  static async fetchImageBuffer(context: common.UIAbilityContext, item: WallpaperItem,
    localRes?: Resource): Promise<ArrayBuffer> {
    if (item.local && localRes) {
      const resMgr = context.resourceManager;
      const fileData = await resMgr.getMediaContent(localRes);
      return fileData.buffer.slice(0);
    }
    const candidates: string[] = [];
    if (item.url && item.url.length > 0) {
      candidates.push(item.url);
    }
    if (item.thumbUrl && item.thumbUrl.length > 0 && candidates.indexOf(item.thumbUrl) < 0) {
      candidates.push(item.thumbUrl);
    }
    let lastErr: Error = new Error('image download failed');
    for (const u of candidates) {
      try {
        // 校验完整性后再返回：截断数据绝不落盘
        return await ImageByteCache.getBytesValidated(u);
      } catch (e) {
        lastErr = e as Error;
      }
    }
    throw lastErr;
  }

  /** 同步版本的完整写入（DocumentViewPicker 场景），返回实际写入字节数 */
  private static writeAllSync(fd: number, buffer: ArrayBuffer): number {
    let offset = 0;
    const total = buffer.byteLength;
    while (offset < total) {
      const chunk = offset === 0 ? buffer : buffer.slice(offset);
      const written = fileIo.writeSync(fd, chunk);
      if (written <= 0) {
        throw new Error('文件写入失败');
      }
      offset += written;
    }
    return offset;
  }

  /**
   * 「存到本地」：DocumentViewPicker DOWNLOAD 模式。
   * 跳过文件选择界面，自动落盘到 Download/<包名>/ 独立目录；
   * 返回的目录 URI 具备持久权限，可在其下创建自定义文件名的文件。
   * preloaded 为预下载字节：传入后与预览/“下载壁纸”共用同一张图，保证“所见即所存”。
   */
  static async saveToDownloadDir(context: common.UIAbilityContext, item: WallpaperItem,
    localRes?: Resource, preloaded?: ArrayBuffer): Promise<string> {
    const options: picker.DocumentSaveOptions = {
      pickerMode: picker.DocumentPickerMode.DOWNLOAD
    };
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save(options);
    if (!uris || uris.length === 0) {
      throw new Error('picker returned empty uri list');
    }
    const dirUri = uris[0];
    // 先取字节，再按真实图片格式定扩展名（修正 .php 等伪后缀接口的保存文件名）
    const buffer = preloaded ?? await ImageSaveUtil.fetchImageBuffer(context, item, localRes);
    const name = ImageSaveUtil.fileNameFor(item, buffer);
    const childUri = dirUri.endsWith('/') ? `${dirUri}${name}` : `${dirUri}/${name}`;
    try {
      // 优先按文档 URI 直接打开（picker 已授予持久 URI 权限）
      const file = fileIo.openSync(childUri, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      try {
        ImageSaveUtil.writeAllSync(file.fd, buffer);
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (e) {
      // 降级：转换为真实文件路径后打开
      const realPath = new fileUri.FileUri(childUri).path;
      const file = fileIo.openSync(realPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      try {
        ImageSaveUtil.writeAllSync(file.fd, buffer);
      } finally {
        fileIo.closeSync(file.fd);
      }
    }
    return childUri;
  }
}
