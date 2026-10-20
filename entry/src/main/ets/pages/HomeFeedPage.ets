import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { WallpaperGrid } from '../common/WallpaperGrid';

/**
 * 首页壁纸信息流
 */
@Component
export struct HomeFeedPage {
  @State items: WallpaperItem[] = [];
  @State loading: boolean = false;
  private store: WallpaperStore = WallpaperStore.getInstance();

  aboutToAppear(): void {
    if (this.items.length === 0) {
      this.loadData(true).catch(() => { });
    }
  }

  async loadData(refresh: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      if (refresh) {
        const fresh = await this.store.refresh();
        this.items = fresh.slice();
      } else {
        const more = await this.store.loadMore();
        this.items = this.items.concat(more);
      }
    } catch (e) {
      // 网络失败时尝试本地内置源兜底
      this.store.setProvider('local');
      const fallback = await this.store.loadMore();
      this.items = this.items.concat(fallback);
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      // 顶部品牌栏
      Row() {
        Text('次元壁纸')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 16 })
        Text('时刻更换最新纸片老婆')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 10 })
        Blank()
        Text($r('app.string.text_refresh'))
          .fontSize(13)
          .fontColor($r('app.color.primary'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.primary_light'))
          .borderRadius(14)
          .margin({ right: 12 })
          .enabled(!this.loading)
          .onClick(() => {
            this.loadData(true).catch(() => { });
          })
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Start)

      WallpaperGrid({
        items: this.items,
        loading: this.loading,
        handler: { onLoadMore: async () => { await this.loadData(false); } }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
