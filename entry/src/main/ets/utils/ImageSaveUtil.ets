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
  /** 保存文件名：ciyuan_<id>_<时间戳>.<扩展名>（按图片地址后缀推断，默认 jpg） */
  static fileNameFor(item: WallpaperItem): string {
    return `ciyuan_${item.id}_${Date.now()}.${ImageSaveUtil.extensionFor(item)}`;
  }

  /** 推断图片扩展名（hdslb 直链为 .webp，部分带 @宽度 处理后缀；取不到时默认 jpg） */
  static extensionFor(item: WallpaperItem): string {
    const src = item.url && item.url.length > 0 ? item.url : item.thumbUrl;
    if (src && src.length > 0) {
      const m = /\.([a-zA-Z0-9]{2,5})(?:[@?]|$)/.exec(src);
      if (m && m[1] && m[1].length > 0) {
        return m[1].toLowerCase();
      }
    }
    return 'jpg';
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
    const name = ImageSaveUtil.fileNameFor(item);
    const childUri = dirUri.endsWith('/') ? `${dirUri}${name}` : `${dirUri}/${name}`;
    const buffer = preloaded ?? await ImageSaveUtil.fetchImageBuffer(context, item, localRes);
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
