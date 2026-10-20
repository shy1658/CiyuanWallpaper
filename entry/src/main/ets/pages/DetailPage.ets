import { router } from '@kit.ArkUI';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { localResFor } from '../common/WallpaperGrid';
import { ImageSaveUtil } from '../utils/ImageSaveUtil';
import { ImageByteCache } from '../utils/ImageByteCache';

/**
 * 壁纸详情页：全屏大图 + 收藏 / 下载壁纸 / 存到本地。
 * 说明：HarmonyOS NEXT 起 setWallpaper 为系统 API，第三方壁纸应用无法直接设置壁纸，
 * 统一做法是保存原图到图库后引导用户在系统设置中选择。
 * 保存到图册使用 SaveButton 安全控件（免申请 WRITE_IMAGEVIDEO 受限权限），
 * 「存到本地」走文档选择器 DOWNLOAD 模式落盘到 Download/包名/ 独立目录。
 */
@Entry
@Component
struct DetailPage {
  /** 当前壁纸数据 */
  @State item: WallpaperItem | undefined = undefined;
  /** 是否已收藏 */
  @State favorite: boolean = false;
  /** 是否正在保存 */
  @State saving: boolean = false;
  /** 是否正在保存到本地目录 */
  @State savingLocal: boolean = false;
  /** 预下载字节解码出的像素图：预览与保存共用同一份字节，确保“所见即所存” */
  @State pixelMap: image.PixelMap | undefined = undefined;
  /** 图片加载状态：loading / ok / error */
  @State loadState: string = 'loading';
  /** 加载失败时的真实错误信息（http 状态码或解码错误），便于定位 */
  @State errorText: string = '';
  /** 双指缩放比例 */
  @State imgScale: number = 1;
  private store: WallpaperStore = WallpaperStore.getInstance();
  /** 预下载的图片二进制（进入页面即开始，点击下载时直接写入，保证在授权窗口内完成） */
  private prefetchPromise: Promise<ArrayBuffer> | undefined = undefined;
  /** 预下载失败标记（失败后点击时改为即时下载） */
  private prefetchFailed: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params && params['item']) {
      try {
        this.item = JSON.parse(params['item']) as WallpaperItem;
        this.favorite = this.store.isFavorite(this.item.id);
        this.startPrefetch();
        // 预下载完成后，用同一份字节解码成像素图用于预览，
        // 保存时也复用这份字节，从根本上避免“预览与保存不是同一张图”
        this.prefetchPromise?.then(async (buf: ArrayBuffer) => {
          try {
            const source = image.createImageSource(buf);
            this.pixelMap = await source.createPixelMap();
            this.loadState = 'ok';
          } catch (e) {
            // 解码失败：显示真实错误而非笼统提示
            this.loadState = 'error';
            this.errorText = '图片解码失败（格式不受支持或文件损坏）';
          }
        }).catch((e: Error) => {
          this.loadState = 'error';
          this.errorText = `图片加载失败：${(e && e.message) ? e.message : '未知错误'}`;
        });
      } catch (e) {
        this.item = undefined;
      }
    }
  }

  /** 进入页面即预下载原图，缩短 SaveButton 授权窗口内的耗时。
   * 所有网络图统一走字节缓存（http 模块 + https→http 回退），与网格缩略图复用同一套网络栈。 */
  private startPrefetch(): void {
    if (!this.item || this.item.local) {
      return;
    }
    this.prefetchPromise = ImageByteCache.getBytes(this.item.url);
    this.prefetchPromise.catch(() => {
      this.prefetchFailed = true;
    });
  }

  /** 取得图片二进制：优先用预下载结果（同一份字节），失败则即时下载 */
  private async obtainBuffer(): Promise<ArrayBuffer> {
    if (this.prefetchPromise && !this.prefetchFailed) {
      try {
        return await this.prefetchPromise;
      } catch (e) {
        this.prefetchFailed = true;
      }
    }
    if (this.item && !this.item.local) {
      // 网络图：统一走字节缓存，保证与预览同一张
      return await ImageByteCache.getBytes(this.item.url);
    }
    const context = getContext(this) as common.UIAbilityContext;
    const res = this.item && this.item.local ? localResFor(this.item.localRes) : undefined;
    return await ImageSaveUtil.fetchImageBuffer(context, this.item as WallpaperItem, res);
  }

  async onFavoriteClick(): Promise<void> {
    if (!this.item) {
      return;
    }
    const nowFavorite = await this.store.toggleFavorite(this.item);
    this.favorite = nowFavorite;
    promptAction.showToast({
      message: nowFavorite ? $r('app.string.text_favorited') : $r('app.string.text_unfavorited'),
      duration: 1500
    });
  }

  /** 申请相册写入权限（SaveButton 授权失败时的降级路径），返回是否已授权 */
  private async requestWritePermission(): Promise<boolean> {
    const context = getContext(this) as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.WRITE_IMAGEVIDEO']);
      return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      return false;
    }
  }

  /**
   * SaveButton 点击回调：授权成功后立即创建媒体资源并写入。
   * buffer 已在进入页面时预下载，写入操作在毫秒级完成。
   */
  private async onSaveButtonClick(result: SaveButtonOnClickResult): Promise<void> {
    if (!this.item || this.saving) {
      return;
    }
    if (result !== SaveButtonOnClickResult.SUCCESS) {
      // 用户取消或授权失败：降级到受限权限路径
      await this.onSaveClickFallback();
      return;
    }
    this.saving = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const buffer = await this.obtainBuffer();
      const name = ImageSaveUtil.fileNameFor(this.item);
      await ImageSaveUtil.writeAssetFromBuffer(context, buffer, name);
      promptAction.showToast({
        message: $r('app.string.text_saved_to_gallery'),
        duration: 3000
      });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.text_save_fail'), duration: 1500 });
    } finally {
      this.saving = false;
    }
  }

  /** 降级路径：申请 WRITE_IMAGEVIDEO 后保存到图库 */
  private async onSaveClickFallback(): Promise<void> {
    if (!this.item || this.saving) {
      return;
    }
    const granted = await this.requestWritePermission();
    if (!granted) {
      promptAction.showToast({ message: $r('app.string.text_save_permission_denied'), duration: 2000 });
      return;
    }
    this.saving = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const res = this.item.local ? localResFor(this.item.localRes) : undefined;
      await ImageSaveUtil.saveToGallery(context, this.item, res);
      promptAction.showToast({
        message: $r('app.string.text_saved_to_gallery'),
        duration: 3000
      });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.text_save_fail'), duration: 1500 });
    } finally {
      this.saving = false;
    }
  }

  /** 「存到本地」：DocumentViewPicker DOWNLOAD 模式，落盘 Download/包名/ 独立目录 */
  private async onSaveLocalClick(): Promise<void> {
    if (!this.item || this.savingLocal) {
      return;
    }
    this.savingLocal = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const res = this.item.local ? localResFor(this.item.localRes) : undefined;
      // 复用与预览同一份预下载字节，确保“存到本地”也是同一张图
      const buffer = await this.obtainBuffer();
      await ImageSaveUtil.saveToDownloadDir(context, this.item, res, buffer);
      promptAction.showToast({
        message: $r('app.string.text_saved_to_download'),
        duration: 3000
      });
    } catch (e) {
      promptAction.showToast({ message: $r('app.string.text_save_fail'), duration: 1500 });
    } finally {
      this.savingLocal = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 全屏黑底
      Column() {
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FF000000')

      // 全屏大图（双指缩放）
      if (this.item) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.item.local) {
            Image(localResFor(this.item.localRes))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else if (this.pixelMap) {
            // 与保存完全一致的预下载字节渲染，确保所见即所存
            Image(this.pixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else if (this.loadState === 'error') {
            // 显示真实错误（http 状态码/解码错误），便于定位问题
            Column() {
              Text(this.errorText.length > 0 ? this.errorText : '图片加载失败')
                .fontSize(14)
                .fontColor('#FFFFFFFF')
                .textAlign(TextAlign.Center)
            }
            .width('80%')
          } else {
            Text('加载中...')
              .fontSize(14)
              .fontColor('#CCFFFFFF')
          }
        }
        .width('100%')
        .height('100%')
        .scale({ x: this.imgScale, y: this.imgScale })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionUpdate((event: GestureEvent) => {
              if (event) {
                this.imgScale = Math.max(1, Math.min(3, event.scale));
              }
            })
        )
      } else {
        Text($r('app.string.text_network_error'))
          .fontSize(14)
          .fontColor('#FFFFFFFF')
      }

      // 顶部返回 + 收藏
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Text('‹')
            .fontSize(30)
            .fontColor('#FFFFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(40)
        .height(40)
        .backgroundColor('#33000000')
        .borderRadius(20)
        .onClick(() => {
          router.back();
        })

        Blank()

        Stack({ alignContent: Alignment.Center }) {
          Text(this.favorite ? '♥' : '♡')
            .fontSize(22)
            .fontColor(this.favorite ? '#FFFF6B9D' : '#FFFFFFFF')
        }
        .width(40)
        .height(40)
        .backgroundColor('#33000000')
        .borderRadius(20)
        .onClick(() => {
          this.onFavoriteClick();
        })
      }
      .width('92%')
      .padding({ left: 4, right: 4 })
      .position({ top: 40 })

      // 底部操作栏
      Column() {
        if (this.item && this.item.tags.length > 0) {
          Row() {
            ForEach(this.item.tags, (tag: string) => {
              Text(`#${tag}`)
                .fontSize(11)
                .fontColor('#FFFFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#33FFFFFF')
                .borderRadius(10)
                .margin({ right: 6 })
            })
          }
          .width('100%')
          .margin({ bottom: 10 })
        }

        Row({ space: 10 }) {
          Button() {
            Text(this.favorite ? '取消收藏' : '收藏')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .height(46)
          .layoutWeight(1)
          .backgroundColor('#FFFFFFFF')
          .borderRadius(23)
          .onClick(() => {
            this.onFavoriteClick();
          })

          // 保存到图库（安全控件：点击即获得临时媒体库写入授权，无需申请存储权限）
          SaveButton({ text: SaveDescription.SAVE_TO_GALLERY })
            .width(132)
            .height(46)
            .fontSize(15)
            .fontColor('#FFFFFFFF')
            .backgroundColor($r('app.color.primary_dark'))
            .borderRadius(23)
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              this.onSaveButtonClick(result).catch(() => { });
            })
        }
        .width('100%')

        // 存到本地（Download/包名/ 独立目录）
        Button() {
          Text(this.savingLocal ? '保存中...' : $r('app.string.text_save_local'))
            .fontSize(14)
            .fontColor($r('app.color.primary_dark'))
        }
        .height(40)
        .width('100%')
        .margin({ top: 10 })
        .backgroundColor('#00FFFFFF')
        .borderRadius(20)
        .border({ width: 1, color: $r('app.color.primary_dark') })
        .enabled(!this.savingLocal)
        .onClick(() => {
          this.onSaveLocalClick().catch(() => { });
        })
      }
      .width('92%')
      .padding({ left: 12, right: 12, top: 14, bottom: 26 })
      .backgroundColor('#E6000000')
      .borderRadius({ topLeft: 20, topRight: 20 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
