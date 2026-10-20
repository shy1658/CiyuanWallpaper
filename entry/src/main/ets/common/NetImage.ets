import { image } from '@kit.ImageKit';
import { ImageByteCache } from '../utils/ImageByteCache';

/**
 * 通用网络图片组件：通过 http 模块下载字节 → 解码 PixelMap 渲染，
 * 带 https→http 回退与失败占位，规避 ArkUI Image(URL) 组件加载图床直链的不确定性。
 * 供收藏列表等需要网络缩略图的场景复用。
 */
@Component
export struct NetImage {
  @Prop src: string = '';
  @Prop imgWidth: Length = '100%';
  @Prop imgHeight: Length = '100%';
  @Prop imgRadius: number = 8;
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State failed: boolean = false;

  aboutToAppear(): void {
    if (this.src && this.src.length > 0) {
      ImageByteCache.getBytes(this.src).then((buf: ArrayBuffer) => {
        return ImageByteCache.toPixelMap(buf);
      }).then((pm: image.PixelMap) => {
        this.pixelMap = pm;
      }).catch(() => {
        this.failed = true;
      });
    } else {
      this.failed = true;
    }
  }

  build() {
    if (this.pixelMap) {
      Image(this.pixelMap)
        .width(this.imgWidth)
        .height(this.imgHeight)
        .objectFit(ImageFit.Cover)
        .borderRadius(this.imgRadius)
    } else {
      Column()
        .width(this.imgWidth)
        .height(this.imgHeight)
        .backgroundColor(this.failed ? '#FFE8EAED' : '#FFF2F4F7')
        .borderRadius(this.imgRadius)
    }
  }
}
