import { WallpaperItem } from '../model/WallpaperItem';
import { WallpaperCard } from './WallpaperCard';

/** 本地预置壁纸资源静态映射（$r 不支持动态拼接） */
export const LOCAL_RES: Resource[] = [
  $r('app.media.wp_1'), $r('app.media.wp_2'), $r('app.media.wp_3'), $r('app.media.wp_4'),
  $r('app.media.wp_5'), $r('app.media.wp_6'), $r('app.media.wp_7'), $r('app.media.wp_8'),
  $r('app.media.wp_9'), $r('app.media.wp_10'), $r('app.media.wp_11'), $r('app.media.wp_12'),
  $r('app.media.wp_13'), $r('app.media.wp_14'), $r('app.media.wp_15'), $r('app.media.wp_16'),
  $r('app.media.wp_17'), $r('app.media.wp_18'), $r('app.media.wp_19'), $r('app.media.wp_20'),
  $r('app.media.wp_21'), $r('app.media.wp_22'), $r('app.media.wp_23'), $r('app.media.wp_24')
];

export function localResFor(name: string | undefined): Resource {
  if (!name) {
    return LOCAL_RES[0];
  }
  const num = parseInt(name.replace('wp_', ''), 10);
  if (isNaN(num) || num < 1 || num > LOCAL_RES.length) {
    return LOCAL_RES[0];
  }
  return LOCAL_RES[num - 1];
}

/**
 * 上拉加载回调载体。
 * 说明：ArkTS V1 装饰器（@Prop）不允许直接装饰 Function 类型变量，
 * 因此用对象包装回调函数。
 */
export interface LoadMoreHandler {
  onLoadMore: () => Promise<void>;
}

/**
 * 双列瀑布流壁纸组件（上拉无限加载）。
 * 注意：自定义组件禁止手动 new，父页面通过 @Prop handler 注入加载回调。
 */
@Component
export struct WallpaperGrid {
  @Prop items: WallpaperItem[];
  @Prop loading: boolean;
  /** 上拉触底回调，由父页面注入 */
  @Prop handler: LoadMoreHandler = { onLoadMore: async () => { } };

  build() {
    Stack() {
      if (this.items.length === 0 && !this.loading) {
        Column() {
          Image($r('app.media.ic_tab_wallpaper'))
            .width(64)
            .height(64)
            .opacity(0.35)
          Text($r('app.string.text_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        WaterFlow() {
          ForEach(this.items, (item: WallpaperItem, index: number) => {
            FlowItem() {
              WallpaperCard({ item: item, index: index })
            }
            .width('100%')
          }, (item: WallpaperItem) => item.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .padding({ left: 12, right: 12, top: 8, bottom: 24 })
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .onReachEnd(() => {
          if (!this.loading) {
            this.handler.onLoadMore();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
