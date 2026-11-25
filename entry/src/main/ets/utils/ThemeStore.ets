import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger } from './Logger';

const PREF_NAME = 'ciyuan_theme';
const KEY_COLOR_MODE = 'color_mode';

/**
 * AppStorage 中的全局颜色模式键（官方 codelab 推荐做法）：
 * 初始化时写入、配置变化时刷新，UI 用 @StorageLink 订阅即可保持同步。
 */
export const APPSTORAGE_COLOR_MODE: string = 'ciyuan_color_mode';

/**
 * 外观（浅色 / 深色 / 跟随系统）偏好管理。
 *
 * 三态与系统枚举严格对齐（不做自定义数值）：
 *   - COLOR_MODE_NOT_SET：跟随系统
 *   - COLOR_MODE_LIGHT：强制浅色
 *   - COLOR_MODE_DARK：强制深色
 *
 * 生效方式：调用 ApplicationContext.setColorMode()，系统会自动重新解析
 * resources/dark 限定目录下的同名资源，$r('app.color.xxx') 引用随之切换，
 * 无需手写 if/else。注意 SDK 要求该 API 必须在 loadContent 之后调用。
 *
 * 注意：setColorMode 是「覆盖」语义——一旦设为 LIGHT/DARK，
 * 系统级的深浅色变化不再回调 onConfigurationUpdate；只有回到 NOT_SET
 * （跟随系统）时，系统切换才会重新触发回调。
 */
export class ThemeStore {
  private static instance: ThemeStore | undefined;
  private prefs: preferences.Preferences | undefined;
  private mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  /** 外观变更监听（设置页等刷新用） */
  private listeners: Array<(mode: ConfigurationConstant.ColorMode) => void> = [];

  static getInstance(): ThemeStore {
    if (!ThemeStore.instance) {
      ThemeStore.instance = new ThemeStore();
    }
    return ThemeStore.instance;
  }

  /** 读取持久化偏好（不应用，仅供调用方决定何时 setColorMode） */
  async init(context: common.UIAbilityContext): Promise<ConfigurationConstant.ColorMode> {
    if (!this.prefs) {
      this.prefs = await preferences.getPreferences(context, PREF_NAME);
    }
    const raw = this.prefs.getSync(KEY_COLOR_MODE, -1) as number;
    if (raw === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      || raw === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      || raw === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      this.mode = raw;
    } else {
      this.mode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    }
    this.publish();
    return this.mode;
  }

  /** 当前外观模式 */
  getMode(): ConfigurationConstant.ColorMode {
    return this.mode;
  }

  /** 当前是否为「跟随系统」 */
  isFollowSystem(): boolean {
    return this.mode === ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }

  /**
   * 切换外观模式：持久化 + 调用 setColorMode 生效 + 通知监听者。
   * @param mode 目标模式
   * @param context 用于 setColorMode 的上下文
   */
  async setMode(mode: ConfigurationConstant.ColorMode,
    context: common.UIAbilityContext): Promise<void> {
    this.mode = mode;
    try {
      await this.prefs?.put(KEY_COLOR_MODE, mode);
      await this.prefs?.flush();
    } catch (e) {
      Logger.e('ThemeStore', 'persist mode failed', e as Error);
    }
    this.apply(context);
    this.publish();
    this.notify();
  }

  /** 把当前模式应用到应用（setColorMode） */
  apply(context: common.UIAbilityContext): void {
    try {
      context.getApplicationContext().setColorMode(this.mode);
    } catch (e) {
      Logger.e('ThemeStore', 'setColorMode failed', e as Error);
    }
    this.applySystemBar(context);
  }

  /**
   * 状态栏适配：深色模式用深色状态栏底 + 浅色图标，浅色模式反之。
   * 这是深浅色适配的官方三项之一（颜色资源 / 媒体资源 / 状态栏），
   * 不处理的话深色模式下状态栏仍是白底黑字，割裂感明显。
   */
  private applySystemBar(context: common.UIAbilityContext): void {
    try {
      window.getLastWindow(context).then((win: window.Window) => {
        const dark = this.isCurrentlyDark();
        win.setWindowSystemBarProperties({
          statusBarColor: dark ? '#FF12121A' : '#FFF8FA',
          statusBarContentColor: dark ? '#FFEDEDF2' : '#FF33333D',
          navigationBarColor: dark ? '#FF12121A' : '#FFF8FA',
          navigationBarContentColor: dark ? '#FFEDEDF2' : '#FF33333D'
        }).catch((e: Error) => {
          Logger.e('ThemeStore', 'setWindowSystemBarProperties failed', e);
        });
      }).catch((e: Error) => {
        Logger.e('ThemeStore', 'getLastWindow failed', e);
      });
    } catch (e) {
      Logger.e('ThemeStore', 'applySystemBar failed', e as Error);
    }
  }

  /**
   * 当前实际生效的是深色还是浅色。
   * 手动锁定时直接看锁定值；跟随系统时读系统当前的颜色模式。
   */
  private isCurrentlyDark(): boolean {
    if (this.mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
      return true;
    }
    if (this.mode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) {
      return false;
    }
    // 跟随系统：以系统当前配置为准
    try {
      return this.systemDarkMode;
    } catch (e) {
      return false;
    }
  }

  /** 系统当前是否为深色（由 onConfigurationUpdate 更新） */
  private systemDarkMode: boolean = false;

  /** 供 Ability 在配置变化时同步系统深浅色状态 */
  setSystemDarkMode(dark: boolean): void {
    this.systemDarkMode = dark;
  }

  /**
   * 系统颜色模式变化回调（仅在「跟随系统」状态下会触发）。
   * 系统深浅色切换时资源限定符已由系统自动切换，这里只做状态同步与通知。
   */
  onSystemColorModeChanged(context: common.UIAbilityContext): void {
    this.publish();
    this.notify();
    this.apply(context);
  }

  /** 注册外观变更监听 */
  onModeChanged(cb: (mode: ConfigurationConstant.ColorMode) => void): void {
    this.listeners.push(cb);
  }

  /** 同步到 AppStorage，供 @StorageLink 订阅 */
  private publish(): void {
    try {
      AppStorage.setOrCreate(APPSTORAGE_COLOR_MODE, this.mode);
    } catch (e) {
      Logger.e('ThemeStore', 'publish to AppStorage failed', e as Error);
    }
  }

  private notify(): void {
    for (const cb of this.listeners) {
      try {
        cb(this.mode);
      } catch (e) {
        Logger.e('ThemeStore', 'listener error', e as Error);
      }
    }
  }
}
