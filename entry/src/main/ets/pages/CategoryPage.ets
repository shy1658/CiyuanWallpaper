import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperProvider } from '../model/WallpaperSource';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { WallpaperGrid } from '../common/WallpaperGrid';

interface CategoryChip {
  id: string;
  name: string;
}

/**
 * 分类页：按数据源浏览。
 * 分类 chips 由 WallpaperStore 动态生成（聚合源 + 内置源 + 自定义源），
 * 自定义图源增删后通过监听热刷新。
 */
@Component
export struct CategoryPage {
  @State items: WallpaperItem[] = [];
  @State loading: boolean = false;
  @State activeCategory: string = 'ciyuan';
  @State categories: CategoryChip[] = [];
  private store: WallpaperStore = WallpaperStore.getInstance();
  private listenerRegistered: boolean = false;

  /** 由当前“已启用”的 provider 列表生成 chips：
   * 仅启用一个源时只展示该源（不显示冗余的“全部”）；多个源时“全部”置顶用于聚合浏览。 */
  private buildCategories(): CategoryChip[] {
    const providers = this.store.getProviderList();
    if (providers.length <= 1) {
      return providers.map((p: WallpaperProvider): CategoryChip => ({ id: p.id, name: p.name }));
    }
    const list: CategoryChip[] = [{ id: 'aggregate', name: '全部' }];
    for (const p of providers) {
      list.push({ id: p.id, name: p.name });
    }
    return list;
  }

  aboutToAppear(): void {
    this.categories = this.buildCategories();
    // 校准默认选中：若当前选中项不在可用列表（如默认 ciyuan 被关闭），回退到第一个
    const ids = this.categories.map(c => c.id);
    if (ids.indexOf(this.activeCategory) < 0) {
      this.activeCategory = ids.length > 0 ? ids[0] : 'ciyuan';
    }
    if (!this.listenerRegistered) {
      this.listenerRegistered = true;
      this.store.onProvidersChanged(() => {
        this.categories = this.buildCategories();
      });
    }
    this.loadData(true).catch(() => { });
  }

  async loadData(refresh: boolean): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    try {
      if (refresh) {
        this.store.setProvider(this.activeCategory);
        const fresh = await this.store.refresh();
        this.items = fresh.slice();
      } else {
        const more = await this.store.loadMore();
        this.items = this.items.concat(more);
      }
    } catch (e) {
      if (this.activeCategory !== 'local') {
        this.store.setProvider('local');
        const fallback = await this.store.loadMore();
        this.items = this.items.concat(fallback);
      }
    } finally {
      this.loading = false;
    }
  }

  build() {
    Column() {
      // 分类 chips
      Scroll() {
        Row() {
          ForEach(this.categories, (cat: CategoryChip) => {
            Text(cat.name)
              .fontSize(13)
              .fontColor(this.activeCategory === cat.id ? '#FFFFFFFF' : $r('app.color.text_secondary'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.activeCategory === cat.id ? $r('app.color.primary') : $r('app.color.card_background'))
              .borderRadius(16)
              .margin({ right: 8 })
              .onClick(() => {
                if (this.activeCategory !== cat.id) {
                  this.activeCategory = cat.id;
                  this.loadData(true).catch(() => { });
                }
              })
          }, (cat: CategoryChip) => cat.id)
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollBar(BarState.Auto)
      .height(44)

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
