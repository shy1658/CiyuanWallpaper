import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WallpaperItem } from '../model/WallpaperItem';

const PREF_NAME = 'ciyuan_favorites';
const KEY_FAVORITES = 'favorites';

/**
 * 收藏持久化工具（用户首选项）
 */
export class FavoritesStore {
  private static instance: FavoritesStore | undefined;
  private prefs: preferences.Preferences | undefined;
  private items: WallpaperItem[] = [];

  static getInstance(): FavoritesStore {
    if (!FavoritesStore.instance) {
      FavoritesStore.instance = new FavoritesStore();
    }
    return FavoritesStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    const raw = this.prefs.getSync(KEY_FAVORITES, '') as string;
    if (raw && raw.length > 0) {
      try {
        this.items = JSON.parse(raw) as WallpaperItem[];
      } catch (e) {
        this.items = [];
      }
    }
  }

  getAll(): WallpaperItem[] {
    return this.items.slice();
  }

  isFavorite(id: string): boolean {
    return this.items.some(item => item.id === id);
  }

  async add(item: WallpaperItem): Promise<void> {
    if (!this.isFavorite(item.id)) {
      this.items.unshift(item);
      await this.flush();
    }
  }

  async remove(id: string): Promise<void> {
    this.items = this.items.filter(item => item.id !== id);
    await this.flush();
  }

  async toggle(item: WallpaperItem): Promise<boolean> {
    if (this.isFavorite(item.id)) {
      await this.remove(item.id);
      return false;
    }
    await this.add(item);
    return true;
  }

  private async flush(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put(KEY_FAVORITES, JSON.stringify(this.items));
    await this.prefs.flush();
  }
}
