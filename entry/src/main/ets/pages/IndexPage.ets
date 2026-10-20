import { HomeFeedPage } from './HomeFeedPage';
import { CategoryPage } from './CategoryPage';
import { ExplorePage } from './ExplorePage';
import { SettingsPage } from './SettingsPage';

const TAB_TITLES: string[] = ['壁纸', '分类', '发现', '我的'];

@Entry
@Component
struct IndexPage {
  @State currentTab: number = 0;
  private controller: TabsController = new TabsController();

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
        TabContent() {
          HomeFeedPage()
        }.tabBar(this.buildTabBar(0, 'ic_tab_wallpaper'))

        TabContent() {
          CategoryPage()
        }.tabBar(this.buildTabBar(1, 'ic_tab_category'))

        TabContent() {
          ExplorePage()
        }.tabBar(this.buildTabBar(2, 'ic_tab_explore'))

        TabContent() {
          SettingsPage()
        }.tabBar(this.buildTabBar(3, 'ic_tab_mine'))
      }
      .barHeight(56)
      .animationDuration(200)
      .scrollable(true)
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  buildTabBar(index: number, iconBase: string) {
    Column() {
      // 选中态用 _active 后缀的同名资源（内置资源，不依赖设备系统符号）
      Image(this.currentTab === index ? $r(`app.media.${iconBase}_active`) : $r(`app.media.${iconBase}`))
        .width(24)
        .height(24)
      Text(TAB_TITLES[index])
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
