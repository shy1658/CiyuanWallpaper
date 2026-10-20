import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { WallpaperGrid } from '../common/WallpaperGrid';

/**
 * 收藏页：本地持久化的收藏列表
 */
@Entry
@Component
struct FavoritePage {
  @State items: WallpaperItem[] = [];
  @State loading: boolean = false;
  private store: WallpaperStore = WallpaperStore.getInstance();

  aboutToAppear(): void {
    this.items = this.store.getFavorites();
  }

  onShow(): void {
    this.items = this.store.getFavorites();
  }

  build() {
    Column() {
      Row() {
        Text('收藏')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 16 })
        Text(`共 ${this.items.length} 张`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 10 })
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Start)

      WallpaperGrid({
        items: this.items,
        loading: this.loading,
        handler: { onLoadMore: async () => { } }
      })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
