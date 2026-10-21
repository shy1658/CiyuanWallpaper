import { router } from '@kit.ArkUI';
import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { WallpaperGrid } from '../common/WallpaperGrid';
import { HistoryStore } from '../utils/HistoryStore';

/**
 * 历史浏览记录页：按时间倒序（最新在前）展示浏览过的壁纸，点击可重新进入详情。
 */
@Entry
@Component
struct HistoryPage {
  @State items: WallpaperItem[] = [];
  @State loading: boolean = false;
  private store: WallpaperStore = WallpaperStore.getInstance();

  aboutToAppear(): void {
    this.refresh();
  }

  onShow(): void {
    this.refresh();
  }

  private refresh(): void {
    this.items = HistoryStore.getInstance().getAll().map(h => h.item);
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Text('‹')
            .fontSize(26)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
        }
        .width(36)
        .height(36)
        .onClick(() => {
          router.back();
        })

        Text('历史浏览记录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })

        Blank()

        if (this.items.length > 0) {
          Text('清空')
            .fontSize(14)
            .fontColor($r('app.color.primary_dark'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor('#150084FF')
            .borderRadius(14)
            .onClick(() => {
              HistoryStore.getInstance().clear();
              this.refresh();
            })
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Start)

      if (this.items.length === 0) {
        Column() {
          Image($r('app.media.ic_tab_wallpaper'))
            .width(64)
            .height(64)
            .opacity(0.35)
          Text('还没有浏览记录，去壁纸页逛逛吧')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        WallpaperGrid({
          items: this.items,
          loading: this.loading,
          handler: { onLoadMore: async () => { } }
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
