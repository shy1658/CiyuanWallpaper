import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { Logger, LogEntry } from '../utils/Logger';

/**
 * 日志页：展示自动收集的错误日志（最新在前），支持清空。
 */
@Entry
@Component
struct LogsPage {
  @State logs: LogEntry[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.refresh();
  }

  onShow(): void {
    this.refresh();
  }

  private refresh(): void {
    this.logs = Logger.getInstance().getAll();
    this.loading = false;
  }

  private levelColor(level: string): string {
    switch (level) {
      case 'FATAL': return '#FFE75480';
      case 'ERROR': return '#FFE53935';
      case 'WARN': return '#FFFF9800';
      default: return '#FF6B7785';
    }
  }

  private fmtTime(t: number): string {
    const d = new Date(t);
    const p = (n: number) => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ` +
      `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
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

        Text('日志')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })

        Blank()

        Text('清空')
          .fontSize(14)
          .fontColor($r('app.color.primary_dark'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor('#150084FF')
          .borderRadius(14)
          .onClick(() => {
            Logger.getInstance().clear();
            this.refresh();
            promptAction.showToast({ message: '日志已清空', duration: 1500 });
          })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .justifyContent(FlexAlign.Start)

      if (this.logs.length === 0) {
        Column() {
          Text('暂无日志')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.logs, (log: LogEntry, idx: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(log.level)
                    .fontSize(11)
                    .fontColor(this.levelColor(log.level))
                    .fontWeight(FontWeight.Bold)
                  Text(log.tag)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 8 })
                  Blank()
                  Text(this.fmtTime(log.time))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .margin({ bottom: 4 })
                Text(log.message)
                  .fontSize(12)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .border({
                width: { bottom: 0.5 },
                color: $r('app.color.divider')
              })
            }
          }, (log: LogEntry, idx: number) => `${idx}_${log.time}`)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0, color: Color.Transparent })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
