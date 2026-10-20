import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { WallpaperItem } from '../model/WallpaperItem';

/**
 * 壁纸下载与保存工具。
 *
 * HarmonyOS NEXT（API 12）保存到相册的系统约束：
 * - photoAccessHelper 不支持创建自定义相册（CreateOptions 仅 title/subtype，
 *   createAlbum 为系统 API），第三方应用创建的图片统一进入图库默认图片集合；
 * - 免受限权限保存到图库的官方路径是 SaveButton（安全控件）：点击后获得临时媒体库
 *   访问授权，在授权窗口内创建资源并取得文件句柄，句柄在授权过期后仍可读写；
 * - 「存到本地」走 DocumentViewPicker 的 DOWNLOAD 模式：跳过选择界面，
 *   自动落盘到 Download/<包名>/ 独立目录，返回具备持久权限的目录 URI。
 */
/** 图库媒体资源句柄（createAsset 后取得的 uri 与写句柄） */
interface GalleryAsset {
  uri: string;
  fd: number;
}

export class ImageSaveUtil {
  /** 保存文件名：ciyuan_<id>_<时间戳>.jpg */
  static fileNameFor(item: WallpaperItem): string {
    return `ciyuan_${item.id}_${Date.now()}.jpg`;
  }

  /**
   * 下载壁纸并保存到图库（WRITE_IMAGEVIDEO 受限权限路径）。
   * 作为 SaveButton 授权失败时的降级方案。
   */
  static async saveToGallery(context: common.UIAbilityContext, item: WallpaperItem,
    localRes?: Resource): Promise<string> {
    const buffer = await ImageSaveUtil.fetchImageBuffer(context, item, localRes);
    const name = ImageSaveUtil.fileNameFor(item);
    return await ImageSaveUtil.writeToGallery(context, buffer, name);
  }

  /** 下载图片二进制（网络图）或读取本地预置资源 */
  static async fetchImageBuffer(context: common.UIAbilityContext, item: WallpaperItem,
    localRes?: Resource): Promise<ArrayBuffer> {
    if (item.local && localRes) {
      const resMgr = context.resourceManager;
      const fileData = await resMgr.getMediaContent(localRes);
      return fileData.buffer.slice(0);
    }
    const request = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'Mozilla/5.0 (Linux; Android 13) CiyuanWallpaper/2.11.5' },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 30000
      };
      const resp = await request.request(item.url, opts);
      if (resp.responseCode !== 200) {
        throw new Error(`http ${resp.responseCode}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      request.destroy();
    }
  }

  /**
   * SaveButton 流程第一步（须在临时授权窗口内调用）：
   * 创建图库媒体资源并打开写句柄，返回 uri + fd。
   * 调用方应尽快完成写入（授权窗口 API 12 为 10 秒）。
   */
  static async createGalleryAsset(context: common.UIAbilityContext,
    name: string): Promise<GalleryAsset> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', { title: name });
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE);
    const asset: GalleryAsset = { uri: uri, fd: file.fd };
    return asset;
  }

  /**
   * SaveButton 流程：createAsset → open → write → close。
   * buffer 须提前准备好（预下载），以保证在授权窗口内完成写入。
   * 返回保存后的媒体库 URI。
   */
  static async writeAssetFromBuffer(context: common.UIAbilityContext,
    buffer: ArrayBuffer, name: string): Promise<string> {
    const asset = await ImageSaveUtil.createGalleryAsset(context, name);
    const uri = asset.uri;
    const fd = asset.fd;
    try {
      await fileIo.write(fd, buffer);
    } finally {
      try {
        await fileIo.close(fd);
      } catch (e) {
        // 关闭失败不阻塞主流程
      }
    }
    return uri;
  }

  /** WRITE_IMAGEVIDEO 路径：下载后创建资源并直接写入 */
  private static async writeToGallery(context: common.UIAbilityContext,
    buffer: ArrayBuffer, name: string): Promise<string> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', { title: name });
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_WRITE);
    try {
      await fileIo.write(file.fd, buffer);
    } finally {
      await fileIo.close(file.fd);
    }
    return uri;
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
        fileIo.writeSync(file.fd, buffer);
      } finally {
        fileIo.closeSync(file.fd);
      }
    } catch (e) {
      // 降级：转换为真实文件路径后打开
      const realPath = new fileUri.FileUri(childUri).path;
      const file = fileIo.openSync(realPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      try {
        fileIo.writeSync(file.fd, buffer);
      } finally {
        fileIo.closeSync(file.fd);
      }
    }
    return childUri;
  }
}
