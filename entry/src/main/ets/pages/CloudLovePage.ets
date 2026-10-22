import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { WallpaperItem } from '../model/WallpaperItem';
import { AuthApi, CloudWallpaper } from '../model/AuthApi';
import { AuthStore } from '../utils/AuthStore';
import { NetImage } from '../common/NetImage';

/**
 * 云端收藏 / 我的上传查看页。
 * mode=love：云端收藏（按分组，offset 分页）
 * mode=upload：我的上传（page 分页）
 * 数据来自原版次元壁纸账号体系，需登录后访问。
 */
@Entry
@Component
struct CloudLovePage {
  @State mode: string = 'love';
  @State items: WallpaperItem[] = [];
  @State groups: string[] = [''];
  @State activeGroup: string = '';
  @State groupsLoaded: boolean = false;
  @State loading: boolean = false;
  @State finished: boolean = false;
  @State loggedIn: boolean = false;
  @State errorMsg: string = '';
  private authStore: AuthStore = AuthStore.getInstance();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params && params['mode']) {
      this.mode = params['mode'];
    }
    this.loggedIn = this.authStore.isLoggedIn();
    if (this.loggedIn) {
      this.reload().catch(() => { });
    }
  }

  /** 云端壁纸 → 本地壁纸模型 */
  private toItem(w: CloudWallpaper): WallpaperItem {
    const tags: string[] = [];
    if (w.tags) {
      for (const t of w.tags) {
        if (t && t.length > 0) {
          tags.push(t);
        }
      }
    }
    if (tags.length === 0 && w.author && w.author.length > 0) {
      tags.push(w.author);
    }
    return {
      id: w.id,
      url: w.url,
      thumbUrl: w.thumbUrl && w.thumbUrl.length > 0 ? w.thumbUrl : w.url,
      source: this.mode === 'upload' ? '我的上传' : '云端收藏',
      width: w.width,
      height: w.height,
      tags: tags,
      local: false
    };
  }

  /** 加载分组（收藏模式），'' 代表全部收藏 */
  private async loadGroups(): Promise<void> {
    const session = this.authStore.getSession();
    if (!session) {
      return;
    }
    try {
      const groups = await AuthApi.getLoveGroups(session.token);
      const names: string[] = [''];
      for (const g of groups) {
        if (g.name && g.name.length > 0 && names.indexOf(g.name) < 0) {
          names.push(g.name);
        }
      }
      this.groups = names;
    } catch (e) {
      this.groups = [''];
    } finally {
      this.groupsLoaded = true;
    }
  }

  /** 重新加载（切源/刷新） */
  private async reload(): Promise<void> {
    if (this.loading) {
      return;
    }
    const session = this.authStore.getSession();
    if (!session) {
      this.loggedIn = false;
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      if (this.mode === 'love' && !this.groupsLoaded) {
        await this.loadGroups();
      }
      const fresh = this.mode === 'love'
        ? await AuthApi.getLoves(session.token, this.activeGroup, 0)
        : await AuthApi.getUploads(session.token, 0);
      this.items = fresh.map((w: CloudWallpaper) => this.toItem(w));
      this.finished = fresh.length === 0;
    } catch (e) {
      this.handleError(e as Error);
    } finally {
      this.loading = false;
    }
  }

  /** 加载更多 */
  private async loadMore(): Promise<void> {
    if (this.loading || this.finished) {
      return;
    }
    const session = this.authStore.getSession();
    if (!session) {
      return;
    }
    this.loading = true;
    try {
      const more = this.mode === 'love'
        ? await AuthApi.getLoves(session.token, this.activeGroup, this.items.length)
        : await AuthApi.getUploads(session.token, Math.floor(this.items.length / 20));
      const mapped = more.map((w: CloudWallpaper) => this.toItem(w));
      this.items = this.items.concat(mapped);
      if (more.length === 0) {
        this.finished = true;
      }
    } catch (e) {
      this.handleError(e as Error);
    } finally {
      this.loading = false;
    }
  }

  /** 错误处理：token 失效时清理会话；服务端版本拦截给出友好提示 */
  private handleError(e: Error): void {
    const msg = e.message || '加载失败，请稍后重试';
    if (msg.indexOf('登录') >= 0 || msg.toLowerCase().indexOf('token') >= 0) {
      this.authStore.clearSession().catch(() => { });
      this.loggedIn = false;
      this.errorMsg = '登录已失效，请重新登录';
      return;
    }
    // 服务端要求升级客户端版本（原版账号体系对收藏接口做了版本校验）
    if (msg.indexOf('升级') >= 0) {
      this.errorMsg = '云端收藏需服务端版本支持，当前返回“请升级至最新版”，功能暂不可用（不影响本地收藏）';
      return;
    }
    this.errorMsg = msg;
  }

  private goLogin(): void {
    router.pushUrl({ url: 'pages/LoginPage' }).catch(() => { });
  }

  build() {
    Column() {
      // 顶部返回 + 标题
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Text('‹')
            .fontSize(28)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Bold)
        }
        .width(40)
        .height(40)
        .onClick(() => {
          router.back();
        })
        Text(this.mode === 'upload' ? '我的上传' : '云端收藏')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
        Blank()
        if (this.mode === 'love') {
          Text('刷新')
            .fontSize(13)
            .fontColor($r('app.color.primary_dark'))
            .padding({ left: 12, right: 4 })
            .onClick(() => {
              this.reload().catch(() => { });
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
      .justifyContent(FlexAlign.Start)

      if (!this.loggedIn) {
        // 未登录引导
        Column() {
          Text('登录后可查看云端收藏与我的上传')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
          Button('去登录')
            .height(44)
            .width('60%')
            .fontSize(15)
            .fontColor('#FFFFFFFF')
            .backgroundColor($r('app.color.primary_dark'))
            .borderRadius(22)
            .margin({ top: 16 })
            .onClick(() => {
              this.goLogin();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 分组 chips（仅收藏模式）
        if (this.mode === 'love') {
          Scroll() {
            Row() {
              ForEach(this.groups, (name: string) => {
                Text(name === '' ? '全部收藏' : name)
                  .fontSize(13)
                  .fontColor(this.activeGroup === name ? '#FFFFFFFF' : $r('app.color.text_secondary'))
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .backgroundColor(this.activeGroup === name ? $r('app.color.primary') : $r('app.color.card_background'))
                  .borderRadius(16)
                  .margin({ right: 8 })
                  .onClick(() => {
                    if (this.activeGroup !== name) {
                      this.activeGroup = name;
                      this.reload().catch(() => { });
                    }
                  })
              }, (name: string) => name)
            }
            .padding({ left: 12, right: 12 })
          }
          .scrollBar(BarState.Auto)
          .height(44)
        }

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(12)
            .fontColor('#FFE75480')
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
        }

        if (this.items.length === 0 && !this.loading && this.errorMsg.length === 0) {
          Column() {
            Image($r('app.media.ic_tab_wallpaper'))
              .width(64)
              .height(64)
              .opacity(0.35)
            Text(this.mode === 'upload' ? '还没有上传过作品' : '云端收藏是空的')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.items, (item: WallpaperItem) => {
              ListItem() {
                Row() {
                  NetImage({ src: item.thumbUrl, itemId: item.id, imgWidth: 72, imgHeight: 96, imgRadius: 8 })
                  Column() {
                    Text(item.tags.length > 0 ? item.tags[0] : '云端壁纸')
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${item.width} × ${item.height}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 12 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              }
              .onClick(() => {
                router.pushUrl({ url: 'pages/DetailPage', params: { item: JSON.stringify(item) } })
                  .catch(() => { });
              })
            }, (item: WallpaperItem) => item.id)
          }
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
          .onReachEnd(() => {
            this.loadMore().catch(() => { });
          })
        }

        if (this.loading) {
          Text('加载中...')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .padding({ top: 8, bottom: 12 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
