import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { CustomSource, BUILTIN_SOURCE_DEFS, BuiltinSourceDef } from '../model/WallpaperSource';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { SourceStore } from '../utils/SourceStore';

/**
 * 壁纸源管理页：内置源只读展示 + 自定义源增删。
 * 自定义源持久化于用户首选项，增删后分类页 chips 热刷新。
 */
@Entry
@Component
struct SourceManagePage {
  @State customSources: CustomSource[] = [];
  @State newName: string = '';
  @State newUrl: string = '';
  /** 内置源启用状态（与 SourceStore 的启用集合同步，默认仅次元壁纸启用） */
  @State builtinEnabled: Record<string, boolean> = {};
  private store: WallpaperStore = WallpaperStore.getInstance();
  private listenerRegistered: boolean = false;

  aboutToAppear(): void {
    this.customSources = this.store.getCustomSources();
    this.syncBuiltinEnabled();
    if (!this.listenerRegistered) {
      this.listenerRegistered = true;
      this.store.onProvidersChanged(() => {
        this.customSources = this.store.getCustomSources();
        this.syncBuiltinEnabled();
      });
    }
  }

  /** 从 SourceStore 同步内置源启用状态到 @State */
  private syncBuiltinEnabled(): void {
    const enabled = SourceStore.getInstance().getEnabledBuiltins();
    const map: Record<string, boolean> = {};
    for (const def of BUILTIN_SOURCE_DEFS) {
      map[def.id] = enabled.has(def.id);
    }
    this.builtinEnabled = map;
  }

  /** 切换内置源启用状态 */
  private async onToggleBuiltin(id: string, value: boolean): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await this.store.setBuiltinEnabled(context, id, value);
      this.syncBuiltinEnabled();
    } catch (e) {
      promptAction.showToast({ message: '设置失败，请重试', duration: 1500 });
    }
  }

  /** 添加自定义图源 */
  private async onAddClick(): Promise<void> {
    const url = this.newUrl.trim();
    if (url.length === 0) {
      promptAction.showToast({ message: '请填写图源 API 地址', duration: 1500 });
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      promptAction.showToast({ message: '地址需以 http:// 或 https:// 开头', duration: 1500 });
      return;
    }
    const exists = SourceStore.idForUrl(url);
    if (this.customSources.some(s => s.id === exists)) {
      promptAction.showToast({ message: '该图源已存在', duration: 1500 });
      return;
    }
    let name = this.newName.trim();
    if (name.length === 0) {
      // 未填名称时取域名作为显示名
      try {
        const host = url.replace(/^https?:\/\//, '').split('/')[0];
        name = host.length > 0 ? host : '自定义图源';
      } catch (e) {
        name = '自定义图源';
      }
    }
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await this.store.addCustomSource(context, name, url);
      this.newName = '';
      this.newUrl = '';
      promptAction.showToast({ message: `已添加图源「${name}」`, duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '添加失败，请重试', duration: 1500 });
    }
  }

  /** 删除自定义图源 */
  private async onRemoveClick(source: CustomSource): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await this.store.removeCustomSource(context, source.id);
      promptAction.showToast({ message: `已删除「${source.name}」`, duration: 1500 });
    } catch (e) {
      promptAction.showToast({ message: '删除失败，请重试', duration: 1500 });
    }
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
        Text('壁纸源管理')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
      .justifyContent(FlexAlign.Start)

      Scroll() {
        Column() {
          // 内置图源（可勾选启用，默认仅次元壁纸）
          Text('内置图源（勾选启用，默认仅“次元壁纸”）')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 16, top: 8, bottom: 6 })
          ForEach(BUILTIN_SOURCE_DEFS, (def: BuiltinSourceDef) => {
            Row() {
              Column() {
                Text(def.name)
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                Text(def.id === 'ciyuan' ? '原版官方源（默认）' : '随机/内置图源')
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.builtinEnabled[def.id] ?? false })
                .onChange((value: boolean) => {
                  this.onToggleBuiltin(def.id, value).catch(() => { });
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .backgroundColor($r('app.color.card_background'))
          }, (def: BuiltinSourceDef) => def.id)

          // 自定义图源
          Text(`自定义图源（${this.customSources.length}）`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 16, top: 20, bottom: 6 })
          if (this.customSources.length === 0) {
            Text('暂无自定义图源，添加后可出现在「分类」页')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_background'))
              .width('100%')
          } else {
            ForEach(this.customSources, (source: CustomSource) => {
              Row() {
                Column() {
                  Text(source.name)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                  Text(source.url)
                    .fontSize(10)
                    .fontColor($r('app.color.text_secondary'))
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('删除')
                  .fontSize(13)
                  .fontColor('#FFE75480')
                  .padding({ left: 12, right: 4 })
                  .onClick(() => {
                    this.onRemoveClick(source).catch(() => { });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_background'))
            }, (source: CustomSource) => source.id)
          }

          // 添加自定义图源
          Text('添加自定义图源')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 16, top: 20, bottom: 6 })
          Column() {
            TextInput({ placeholder: '名称（留空则取域名）' })
              .height(44)
              .fontSize(14)
              .backgroundColor('#FFF2F4F7')
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.newName = value;
              })
            TextInput({ placeholder: 'API 地址，如 https://example.com/random.php' })
              .height(44)
              .fontSize(14)
              .backgroundColor('#FFF2F4F7')
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .margin({ top: 10 })
              .onChange((value: string) => {
                this.newUrl = value;
              })
            Button('添加图源')
              .height(44)
              .width('100%')
              .fontSize(15)
              .fontColor('#FFFFFFFF')
              .backgroundColor($r('app.color.primary_dark'))
              .borderRadius(22)
              .margin({ top: 12 })
              .onClick(() => {
                this.onAddClick().catch(() => { });
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
