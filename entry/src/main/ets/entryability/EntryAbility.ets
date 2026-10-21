import { AbilityConstant, UIAbility, Want, errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { FavoritesStore } from '../utils/FavoritesStore';
import { SourceStore } from '../utils/SourceStore';
import { AuthStore } from '../utils/AuthStore';
import { WallpaperStore } from '../viewmodel/WallpaperStore';
import { Logger } from '../utils/Logger';
import { HistoryStore } from '../utils/HistoryStore';

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
          Logger.fatal('Global', 'exception: ' + errObject.message + ' | ' + (errObject.stack ?? ''));
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
    windowStage.loadContent('pages/IndexPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'CiyuanWallpaper', 'load content failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'CiyuanWallpaper', 'load content success');
    });
  }
}
