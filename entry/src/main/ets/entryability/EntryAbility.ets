import {
  AbilityConstant, UIAbility, Want, errorManager, Configuration, ConfigurationConstant
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { FavoritesStore } from '../utils/FavoritesStore';
import { SourceStore } from '../utils/SourceStore';
import { AuthStore } from '../utils/AuthStore';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { Logger, describeError } from '../utils/Logger';
import { HistoryStore } from '../utils/HistoryStore';
import { ThemeStore } from '../utils/ThemeStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'CiyuanWallpaper', 'EntryAbility onCreate');
    const context = this.context;

    // 日志与历史持久化初始化（需在其它 store 之前，便于后续统一收集错误）
    Logger.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'Logger initialized');
      })
      .catch((e: Error) => {
        hilog.error(0x0000, 'CiyuanWallpaper', 'Logger init failed: %{public}s', e.message);
      });
    HistoryStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'HistoryStore initialized');
      })
      .catch((e: Error) => {
        hilog.error(0x0000, 'CiyuanWallpaper', 'HistoryStore init failed: %{public}s', e.message);
      });

    // 全局未捕获异常监听：捕获后写入 FATAL 日志（不主动退出，保持应用可用）
    try {
      errorManager.on('error', {
        onUnhandledException(errMsg: string): void {
          Logger.fatal('Global', 'uncaught: ' + errMsg);
        },
        onException(errObject: Error): void {
          Logger.fatal('Global', 'exception: ' + describeError(errObject));
        }
      });
    } catch (e) {
      hilog.error(0x0000, 'CiyuanWallpaper', 'register errorManager failed: %{public}s', (e as Error).message);
    }

    FavoritesStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'FavoritesStore initialized');
      })
      .catch((e: Error) => {
        Logger.e('FavoritesStore', 'init failed', e);
        hilog.error(0x0000, 'CiyuanWallpaper', 'init failed: %{public}s', e.message);
      });
    WallpaperStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'WallpaperStore initialized (custom sources loaded)');
      })
      .catch((e: Error) => {
        Logger.e('WallpaperStore', 'init failed', e);
        hilog.error(0x0000, 'CiyuanWallpaper', 'WallpaperStore init failed: %{public}s', e.message);
      });
    AuthStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'AuthStore initialized');
      })
      .catch((e: Error) => {
        Logger.e('AuthStore', 'init failed', e);
        hilog.error(0x0000, 'CiyuanWallpaper', 'AuthStore init failed: %{public}s', e.message);
      });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 读取持久化的外观偏好（浅色/深色/跟随系统）。
    // 注意：setColorMode 必须在 loadContent 之后调用（SDK 明确要求窗口与页面已创建），
    // 因此这里只读取偏好，实际生效放在 loadContent 的回调里。
    ThemeStore.getInstance().init(this.context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'ThemeStore initialized');
      })
      .catch((e: Error) => {
        Logger.e('ThemeStore', 'init failed', e);
      })
      .finally(() => {
        windowStage.loadContent('pages/IndexPage', (err) => {
          if (err.code) {
            hilog.error(0x0000, 'CiyuanWallpaper', 'load content failed: %{public}s', JSON.stringify(err));
            return;
          }
          hilog.info(0x0000, 'CiyuanWallpaper', 'load content success');
          // 读取系统当前深浅色（跟随系统时用于状态栏配色判断）
          ThemeStore.getInstance().setSystemDarkMode(
            this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
          // 页面就绪后再应用外观，避免启动瞬间先闪一下默认浅色再切到目标模式
          ThemeStore.getInstance().apply(this.context);
        });
      });
  }

  /**
   * 配置变化回调（含系统深浅色切换）。
   * 仅在「跟随系统」状态下才会因系统深浅色变化而触发；
   * 手动锁定浅色/深色时 setColorMode 已覆盖，资源不会再变。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(0x0000, 'CiyuanWallpaper', 'configuration updated, colorMode=%{public}d',
      newConfig.colorMode);
    // 记录系统当前深浅色（跟随系统时用于状态栏配色判断）
    const sysDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    ThemeStore.getInstance().setSystemDarkMode(sysDark);
    ThemeStore.getInstance().onSystemColorModeChanged(this.context);
  }
}
