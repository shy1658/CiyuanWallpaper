import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { FavoritesStore } from '../utils/FavoritesStore';
import { SourceStore } from '../utils/SourceStore';
import { AuthStore } from '../utils/AuthStore';
import { WallpaperStore } from '../viewmodel/WallpaperStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'CiyuanWallpaper', 'EntryAbility onCreate');
    const context = this.context;
    FavoritesStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'FavoritesStore initialized');
      })
      .catch((e: Error) => {
        hilog.error(0x0000, 'CiyuanWallpaper', 'init failed: %{public}s', e.message);
      });
    WallpaperStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'WallpaperStore initialized (custom sources loaded)');
      })
      .catch((e: Error) => {
        hilog.error(0x0000, 'CiyuanWallpaper', 'WallpaperStore init failed: %{public}s', e.message);
      });
    AuthStore.getInstance().init(context)
      .then(() => {
        hilog.info(0x0000, 'CiyuanWallpaper', 'AuthStore initialized');
      })
      .catch((e: Error) => {
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
