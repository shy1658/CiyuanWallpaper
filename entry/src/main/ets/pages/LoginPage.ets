import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AuthApi } from '../model/AuthApi';
import { AuthStore } from '../utils/AuthStore';

/**
 * 登录页：使用原版次元壁纸（13th.tech）账号登录。
 * 登录成功后会话持久化，可用于查看云端收藏与我的上传。
 */
@Entry
@Component
struct LoginPage {
  @State account: string = '';
  @State pwd: string = '';
  @State loading: boolean = false;
  @State errorMsg: string = '';
  private authStore: AuthStore = AuthStore.getInstance();

  private async onLoginClick(): Promise<void> {
    if (this.loading) {
      return;
    }
    const account = this.account.trim();
    const pwd = this.pwd;
    if (account.length === 0 || pwd.length === 0) {
      this.errorMsg = '请输入账号和密码';
      return;
    }
    this.loading = true;
    this.errorMsg = '';
    try {
      const user = await AuthApi.login(account, pwd);
      await this.authStore.saveSession(user);
      promptAction.showToast({ message: `欢迎回来，${user.username}`, duration: 1500 });
      router.back();
    } catch (e) {
      const err = e as Error;
      this.errorMsg = err.message && err.message.length > 0 ? err.message : '登录失败，请稍后重试';
    } finally {
      this.loading = false;
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
        Text('登录')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 8 })
      .justifyContent(FlexAlign.Start)

      Column() {
        Image($r('app.media.app_icon'))
          .width(64)
          .height(64)
          .borderRadius(32)
          .margin({ top: 24 })
        Text('次元壁纸')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 12 })
        Text('登录后可查看云端收藏与我的上传')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })

        TextInput({ placeholder: '账号' })
          .height(48)
          .fontSize(15)
          .backgroundColor('#FFF2F4F7')
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .margin({ top: 28 })
          .onChange((value: string) => {
            this.account = value;
          })

        TextInput({ placeholder: '密码' })
          .type(InputType.Password)
          .height(48)
          .fontSize(15)
          .backgroundColor('#FFF2F4F7')
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .margin({ top: 12 })
          .showPasswordIcon(true)
          .onChange((value: string) => {
            this.pwd = value;
          })

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(12)
            .fontColor('#FFE75480')
            .width('100%')
            .margin({ top: 10 })
        }

        Button() {
          Text(this.loading ? '登录中...' : '登 录')
            .fontSize(16)
            .fontColor('#FFFFFFFF')
        }
        .height(48)
        .width('100%')
        .backgroundColor($r('app.color.primary_dark'))
        .borderRadius(24)
        .margin({ top: 20 })
        .enabled(!this.loading)
        .onClick(() => {
          this.onLoginClick().catch(() => { });
        })

        Text('账号信息仅用于访问次元壁纸开放接口，不会上传至第三方')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16, bottom: 24 })
      }
      .width('86%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
