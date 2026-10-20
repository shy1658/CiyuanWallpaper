import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { WallpaperItem } from '../model/WallpaperItem';
import { localResFor } from './WallpaperGrid';
import { ImageByteCache } from '../utils/ImageByteCache';

/**
 * 单张壁纸卡片（瀑布流单元）。
 * 统一通过 http 模块下载字节 → 解码 PixelMap 渲染（而非 ArkUI Image(URL) 组件），
 * 与详情页/保存复用同一套网络栈，规避 Image 组件加载图床直链的不确定性。
 * - 本地预置图：直接渲染资源；
 * - 网络图（稳定源/易变源）：进入即按地址预下载字节并渲染；
 *   易变源（随机图/自定义随机）网格与详情用同一 URL，命中同一缓存即同一张图。
 */
@Component
export struct WallpaperCard {
  @Prop item: WallpaperItem = {
    id: '', url: '', thumbUrl: '', source: '', width: 0, height: 0, tags: [], local: false, volatile: false
  };
  @Prop index: number = 0;
  /** 预下载解码出的像素图 */
  @State pixelMap: image.PixelMap | undefined = undefined;
  /** 加载失败标记（显示可见占位，便于定位） */
  @State loadFailed: boolean = false;

  aboutToAppear(): void {
    if (!this.item.local) {
      // 缩略图优先用 thumbUrl（更小）；易变源 thumbUrl 恒等于 url，与详情页缓存键一致
      const src = (this.item.thumbUrl && this.item.thumbUrl.length > 0) ? this.item.thumbUrl : this.item.url;
      ImageByteCache.getBytes(src).then((buf: ArrayBuffer) => {
        return ImageByteCache.toPixelMap(buf);
      }).then((pm: image.PixelMap) => {
        this.pixelMap = pm;
      }).catch(() => {
        this.loadFailed = true;
      });
    }
  }

  private heightFor(index: number): number {
    const heights: number[] = [220, 260, 300, 240, 280, 200, 320, 250];
    return heights[index % heights.length];
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.item.local) {
        Image(localResFor(this.item.localRes))
          .width('100%')
          .height(this.heightFor(this.index))
          .objectFit(ImageFit.Cover)
          .borderRadius(14)
      } else if (this.pixelMap) {
        Image(this.pixelMap)
          .width('100%')
          .height(this.heightFor(this.index))
          .objectFit(ImageFit.Cover)
          .borderRadius(14)
      } else if (this.loadFailed) {
        // 加载失败：可见占位（不再是静默灰块，便于判断是“没图”还是“加载失败”）
        Column() {
          Text('加载失败')
            .fontSize(11)
            .fontColor('#FF9AA0A6')
        }
        .width('100%')
        .height(this.heightFor(this.index))
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFE8EAED')
        .borderRadius(14)
      } else {
        // 字节下载中占位
        Column()
          .width('100%')
          .height(this.heightFor(this.index))
          .backgroundColor('#FFF2F4F7')
          .borderRadius(14)
      }
      // 底部来源标签
      Row() {
        Text(this.item.source)
          .fontSize(9)
          .fontColor('#FFFFFFFF')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#66000000')
          .borderRadius(6)
          .margin({ left: 8, bottom: 8 })
      }
      .width('100%')
    }
    .width('100%')
    .onClick(() => {
      router.pushUrl({ url: 'pages/DetailPage', params: { item: JSON.stringify(this.item) } })
        .catch(() => { });
    })
  }
}
