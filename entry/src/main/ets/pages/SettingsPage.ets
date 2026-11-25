import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { AuthStore } from '../utils/AuthStore';
import { HistoryStore } from '../utils/HistoryStore';
import { Logger } from '../utils/Logger';
import { ThemeStore, APPSTORAGE_COLOR_MODE } from '../utils/ThemeStore';

/**
 * 我的 / 设置页
 */
@Component
export struct SettingsPage {
  @State favoriteCount: number = 0;
  @State loggedIn: boolean = false;
  @State username: string = '';
  @State isPro: boolean = false;
  @State sourceCount: number = 0;
  @State historyCount: number = 0;
  @State logCount: number = 0;
  /** 外观模式（订阅 AppStorage，随系统/手动切换实时更新） */
  @StorageLink(APPSTORAGE_COLOR_MODE) themeMode: ConfigurationConstant.ColorMode =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  private store: WallpaperStore = WallpaperStore.getInstance();
  private authStore: AuthStore = AuthStore.getInstance();
  private themeStore: ThemeStore = ThemeStore.getInstance();
  private listenerRegistered: boolean = false;

  /** 同步登录态与图源数量到 UI 状态 */
  private syncState(): void {
    const session = this.authStore.getSession();
    this.loggedIn = this.authStore.isLoggedIn();
    this.username = session ? session.username : '';
    this.isPro = session ? session.isPro : false;
    this.sourceCount = this.store.getCustomSources().length;
    this.favoriteCount = this.store.getFavorites().length;
    this.historyCount = HistoryStore.getInstance().getAll().length;
    this.logCount = Logger.getInstance().count();
    this.themeMode = this.themeStore.getMode();
  }

  /** 外观模式中文描述 */
  private themeLabel(): string {
    const mode = this.themeStore.getMode();
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      return '浅色模式';
    }
    if (mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return '深色模式';
    }
    return '跟随系统';
  }

  /** 弹出外观选择对话框（跟随系统 / 浅色 / 深色） */
  private onThemeRowClick(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    promptAction.showDialog({
      title: '外观',
      message: '选择应用配色方式，可跟随系统深浅色自动切换',
      buttons: [
        { text: '跟随系统', color: $r('app.color.text_secondary') },
        { text: '浅色模式', color: $r('app.color.text_secondary') },
        { text: '深色模式', color: $r('app.color.error_color') }
      ]
    }).then((dialogResult: promptAction.ShowDialogSuccessResponse) => {
      let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (dialogResult.index === 1) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (dialogResult.index === 2) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      this.themeStore.setMode(target, ctx)
        .then(() => {
          this.themeMode = target;
          promptAction.showToast({ message: `已切换为${this.themeLabel()}`, duration: 1200 });
        })
        .catch(() => {
          promptAction.showToast({ message: '切换失败，请重试', duration: 1500 });
        });
    }).catch(() => { });
  }

  onShow(): void {
    this.syncState();
  }

  aboutToAppear(): void {
    this.syncState();
    if (!this.listenerRegistered) {
      this.listenerRegistered = true;
      this.authStore.onSessionChanged(() => {
        this.syncState();
      });
      this.store.onProvidersChanged(() => {
        this.sourceCount = this.store.getCustomSources().length;
      });
    }
  }

  /** 用户行点击：未登录 → 登录页；已登录 → 确认退出 */
  private onUserRowClick(): void {
    if (!this.loggedIn) {
      router.pushUrl({ url: 'pages/LoginPage' }).catch(() => { });
      return;
    }
    promptAction.showDialog({
      title: '退出登录',
      message: `当前账号：${this.username}，退出后需重新登录才能查看云端收藏`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        {
          text: '退出',
          color: $r('app.color.error_color')
        }
      ]
    }).then((dialogResult: promptAction.ShowDialogSuccessResponse) => {
      if (dialogResult.index === 1) {
        this.authStore.clearSession().catch(() => { });
        promptAction.showToast({ message: '已退出登录', duration: 1500 });
      }
    }).catch(() => { });
  }

  build() {
    Column() {
      // 头部
      Row() {
        Image($r('app.media.app_icon'))
          .width(56)
          .height(56)
          .borderRadius(28)
        Column() {
          Text('次元壁纸')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('HarmonyOS 版 · v2.11.77')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .margin({ left: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Start)

      List() {
        // 账号行
        ListItem() {
          this.buildRow(
            this.loggedIn ? this.username : '登录账号',
            this.loggedIn
              ? (this.isPro ? '高级版用户 · 点击退出登录' : '已登录 · 点击退出登录')
              : '登录后可查看云端收藏',
            () => {
              this.onUserRowClick();
            })
        }

        // 云端收藏（登录后可见）
        if (this.loggedIn) {
          ListItem() {
            this.buildRow('云端收藏', '查看账号在原版次元壁纸的收藏', () => {
              router.pushUrl({ url: 'pages/CloudLovePage', params: { mode: 'love' } }).catch(() => { });
            })
          }
        }

        ListItem() {
          this.buildRow('我的收藏', `共 ${this.favoriteCount} 张`, () => {
            router.pushUrl({ url: 'pages/FavoritePage' }).catch(() => { });
          })
        }

        ListItem() {
          this.buildRow('历史浏览记录', `共 ${this.historyCount} 条`, () => {
            router.pushUrl({ url: 'pages/HistoryPage' }).catch(() => { });
          })
        }

        ListItem() {
          this.buildRow('日志', this.logCount > 0 ? `未读 ${this.logCount} 条` : '自动收集运行错误', () => {
            router.pushUrl({ url: 'pages/LogsPage' }).catch(() => { });
          })
        }

        // 外观（浅色 / 深色 / 跟随系统）
        ListItem() {
          this.buildRow('外观', this.themeLabel(), () => {
            this.onThemeRowClick();
          })
        }

        // 壁纸源管理
        ListItem() {
          this.buildRow('壁纸源', `内置 5 个 · 自定义 ${this.sourceCount} 个`, () => {
            router.pushUrl({ url: 'pages/SourceManagePage' }).catch(() => { });
          })
        }

        ListItem() {
          this.buildRow('关于', '次元壁纸 HarmonyOS 移植版 · 最低支持 API 12', () => {
            router.pushUrl({ url: 'pages/AboutPage' }).catch(() => { });
          })
        }
      }
      .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  buildRow(title: string, subtitle: string, onClick: () => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Text(subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(onClick)
  }

}
