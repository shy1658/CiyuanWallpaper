import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { localResFor } from '../common/WallpaperGrid';
import { ImageSaveUtil } from '../utils/ImageSaveUtil';
import { ImageByteCache } from '../utils/ImageByteCache';
import { Logger } from '../utils/Logger';
import { HistoryStore } from '../utils/HistoryStore';

/** 预览加载结果：原始字节 + 解码后的像素图（保存复用同一份字节，所见即所存） */
interface PreviewResult {
  buf: ArrayBuffer;
  pm: image.PixelMap;
}

/**
 * 壁纸详情页：全屏大图 + 收藏 / 存到本地。
 * 说明：HarmonyOS NEXT 起 setWallpaper 为系统 API，第三方壁纸应用无法直接设置壁纸，
 * 「存到本地」走文档选择器 DOWNLOAD 模式落盘到 Download/包名/ 独立目录。
 * 进入页面即记录到「历史浏览记录」。
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
  /** 当前预览像素图（缩略图先出、原图校验通过后升级高清） */
  @State pixelMap: image.PixelMap | undefined = undefined;
  /** 图片加载状态：loading / ok / error */
  @State loadState: string = 'loading';
  /** 加载失败时的真实错误信息（http 状态码或解码错误），便于定位 */
  @State errorText: string = '';
  /** 双指缩放比例 */
  @State imgScale: number = 1;
  private store: WallpaperStore = WallpaperStore.getInstance();
  /** 缩略图加载任务（快速首屏，体积小） */
  private thumbPromise: Promise<PreviewResult> | undefined = undefined;
  /** 原图加载任务（完整性与解码双校验通过后升级为高清预览，并作为保存首选） */
  private originalPromise: Promise<PreviewResult> | undefined = undefined;
  /** 缩略图字节（保存兜底：原图不可用时保存它） */
  private prefetchedBuffer: ArrayBuffer | undefined = undefined;
  /** 原图字节（保存首选：能正常加载的最清晰版本） */
  private originalBuffer: ArrayBuffer | undefined = undefined;
  /** 是否存在与原图不同的缩略图地址（易变源两者相同） */
  private hasOriginal: boolean = false;
  /** 缩略图/原图的结束与成功状态（两者都失败才展示错误） */
  private thumbSettled: boolean = false;
  private thumbOk: boolean = false;
  private originalSettled: boolean = false;
  private originalOk: boolean = false;
  /** 当前预览是否已升级为原图（防止缩略图晚到把高清图顶掉） */
  private showingOriginal: boolean = false;
  /** 最后一次失败的真实原因（全部失败时展示） */
  private lastErr: Error = new Error('image load failed');
  /** 本次保存是否回退到了缩略图字节，用于提示用户 */
  private usedFallbackBuffer: boolean = false;

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params && params['item']) {
      try {
        this.item = JSON.parse(params['item']) as WallpaperItem;
        this.favorite = this.store.isFavorite(this.item.id);
        // 记录浏览历史（去重置顶、按时间倒序）
        HistoryStore.getInstance().record(this.item);
        this.startPrefetch();
      } catch (e) {
        this.item = undefined;
        Logger.e('DetailPage', '解析壁纸参数失败', e as Error);
      }
    }
  }

  /**
   * 进入页面即开始加载，两路并行：
   * 1) 缩略图：体积小（约 100KB），先出图，保证首屏不空等；
   * 2) 原图：完整性与解码双校验通过后，升级为高清预览，并作为保存首选。
   * 原图被图床风控（http 567）、下载截断或解码失败时，保留缩略图且绝不落盘坏数据。
   */
  private startPrefetch(): void {
    const item = this.item;
    if (!item || item.local) {
      return;
    }
    const thumb = (item.thumbUrl && item.thumbUrl.length > 0) ? item.thumbUrl : item.url;
    const origin = item.url;
    this.hasOriginal = origin.length > 0 && origin !== thumb;

    // 1) 缩略图：快速首屏
    this.thumbPromise = this.loadSource(thumb);
    this.thumbPromise.then((res: PreviewResult) => {
      this.thumbSettled = true;
      this.thumbOk = true;
      this.prefetchedBuffer = res.buf;
      // 原图已经先到时不回退到低清
      if (!this.showingOriginal) {
        this.pixelMap = res.pm;
        this.loadState = 'ok';
      }
    }).catch((e: Error) => {
      this.thumbSettled = true;
      this.lastErr = e;
      Logger.e('DetailPage', '缩略图加载失败', e);
      this.reportIfAllFailed();
    });

    // 2) 原图：校验通过后升级为高清
    if (this.hasOriginal) {
      this.originalPromise = this.loadSource(origin);
      this.originalPromise.then((res: PreviewResult) => {
        this.originalSettled = true;
        this.originalOk = true;
        this.originalBuffer = res.buf;
        this.showingOriginal = true;
        this.pixelMap = res.pm;
        this.loadState = 'ok';
      }).catch((e: Error) => {
        this.originalSettled = true;
        this.lastErr = e;
        Logger.e('DetailPage', '原图加载失败', e);
        this.reportIfAllFailed();
      });
    } else {
      // 易变源：thumbUrl === url，缩略图就是原图
      this.originalSettled = true;
    }
  }

  /** 两路都失败才展示错误（单路失败由另一路兜底） */
  private reportIfAllFailed(): void {
    if (this.loadState === 'ok') {
      return;
    }
    if (this.thumbSettled && this.originalSettled && !this.thumbOk && !this.originalOk) {
      this.loadState = 'error';
      this.errorText = `图片加载失败：${(this.lastErr && this.lastErr.message) ? this.lastErr.message : '未知错误'}`;
    }
  }

  /** 加载单个地址：完整性校验 + 缩小解码；任一步失败即抛错，由调用方决定是否换源 */
  private async loadSource(u: string): Promise<PreviewResult> {
    // 按条目 id 取字节：易变源（随机图）一张图只下载一次，网格/详情/保存共用同一份
    const buf = await ImageByteCache.getBytesValidatedForItem(this.item!.id, u);
    // 预览按 2048 长边缩小解码：避免大图超出 GPU 纹理上限导致解码失败
    const pm = await ImageByteCache.toPixelMapScaled(buf, 2048);
    return { buf: buf, pm: pm };
  }

  /** 带超时的等待（毫秒）：超时返回 undefined，由调用方走回退逻辑 */
  private async withTimeout(p: Promise<PreviewResult>, ms: number): Promise<PreviewResult | undefined> {
    let timer: number | undefined = undefined;
    try {
      const timeout = new Promise<PreviewResult | undefined>((resolve) => {
        timer = setTimeout(() => resolve(undefined), ms);
      });
      return await Promise.race([p, timeout]);
    } finally {
      if (timer !== undefined) {
        clearTimeout(timer);
      }
    }
  }

  /**
   * 取得保存用图片二进制：原图优先、缩略图兜底，均通过完整性校验。
   * 本地保存走 DocumentViewPicker 持久授权，无 SaveButton 10 秒窗口限制，可等待原图下载。
   */
  private async obtainBuffer(): Promise<ArrayBuffer> {
    this.usedFallbackBuffer = false;
    const item = this.item;
    if (item && !item.local) {
      // 1) 原图已缓存：直接返回
      if (this.originalBuffer) {
        return this.originalBuffer;
      }
      // 2) 等待大原图下载（本地保存无窗口限制，原图优先）
      if (this.hasOriginal && this.originalPromise && !this.originalSettled) {
        try {
          const res = await this.withTimeout(this.originalPromise, 6000);
          if (res) {
            this.originalBuffer = res.buf;
            return res.buf;
          }
        } catch (e) {
          // 原图加载失败：回退缩略图
        }
      }
      // 3) 缩略图已缓存：兜底返回
      if (this.prefetchedBuffer) {
        this.usedFallbackBuffer = true;
        return this.prefetchedBuffer;
      }
      // 4) 缩略图仍在加载：最多等 4 秒
      if (this.thumbPromise && !this.thumbSettled) {
        try {
          const res = await this.withTimeout(this.thumbPromise, 4000);
          if (res) {
            this.prefetchedBuffer = res.buf;
            this.usedFallbackBuffer = true;
            return res.buf;
          }
        } catch (e) {
          // 缩略图也失败：走即时下载
        }
      }
      // 3) 即时下载：原图优先、缩略图兜底，均需通过校验
      const order: string[] = [];
      if (item.url && item.url.length > 0) {
        order.push(item.url);
      }
      if (item.thumbUrl && item.thumbUrl.length > 0 && order.indexOf(item.thumbUrl) < 0) {
        order.push(item.thumbUrl);
      }
      let lastErr: Error = new Error('image download failed');
      for (let i = 0; i < order.length; i++) {
        try {
          const buf = await ImageByteCache.getBytesValidatedForItem(this.item!.id, order[i]);
          if (i > 0) {
            this.usedFallbackBuffer = true;
          }
          return buf;
        } catch (e) {
          lastErr = e as Error;
        }
      }
      throw lastErr;
    }
    // 本地预置图
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

  /** 「存到本地」：DocumentViewPicker DOWNLOAD 模式，落盘 Download/包名/ 独立目录 */
  private async onSaveLocalClick(): Promise<void> {
    if (!this.item || this.savingLocal) {
      return;
    }
    this.savingLocal = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const res = this.item.local ? localResFor(this.item.localRes) : undefined;
      // 原图优先（后台已预下载），原图不可达时回退预览字节，保证“存到本地”不失败
      const buffer = await this.obtainBuffer();
      await ImageSaveUtil.saveToDownloadDir(context, this.item, res, buffer);
      if (this.usedFallbackBuffer) {
        promptAction.showToast({
          message: '原图不可用（数据不完整或加载失败），已保存当前预览图',
          duration: 3000
        });
      } else {
        promptAction.showToast({
          message: $r('app.string.text_saved_to_download'),
          duration: 3000
        });
      }
    } catch (e) {
      Logger.e('DetailPage', '保存到本地失败', e as Error);
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
