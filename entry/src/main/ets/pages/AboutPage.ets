import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

/**
 * 关于页：作者、声明（未完全移植）等信息。
 */
@Entry
@Component
struct AboutPage {
  private readonly author: string = 'shy1658';
  private readonly repo: string = 'https://github.com/shy1658/CiyuanWallpaper';

  @Builder
  section(title: string, body: string, onClick?: () => void) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 6 })
      Text(body)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
    .margin({ bottom: 12 })
    .onClick(() => {
      if (onClick) {
        onClick();
      }
    })
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
        Text('关于')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Start)

      Scroll() {
        Column() {
          // 头部
          Column() {
            Image($r('app.media.app_icon'))
              .width(72)
              .height(72)
              .borderRadius(16)
            Text('次元壁纸')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ top: 10 })
            Text('HarmonyOS 移植版 · v2.11.71')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 8, bottom: 20 })

          // 作者
          this.section('作者', `GitHub：@${this.author}`)

          // 开源仓库
          this.section('开源仓库', this.repo, () => {
            promptAction.showToast({ message: '仓库地址已复制', duration: 1500 });
          })

          // 声明
          this.section(
            '声明',
            '本应用为「次元壁纸」的 HarmonyOS 移植版（非官方）。\n' +
            '⚠ 未完全移植：部分原版能力（如系统壁纸设置、云端自动同步、个别定制图源等）' +
            '尚未在 HarmonyOS 端实现，后续逐步补全。\n' +
            '壁纸数据来自公开的二次元图床聚合，版权归原作者所有，仅作个人欣赏使用。'
          )

          // 数据来源
          this.section('数据来源', '公开二次元图床聚合（含次元壁纸官方源及多个社区图源）')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
