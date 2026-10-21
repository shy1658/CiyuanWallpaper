import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WallpaperItem } from '../model/WallpaperItem';

/** 历史浏览记录条目 */
export interface HistoryEntry {
  item: WallpaperItem;
  time: number;
}

const PREF_NAME = 'ciyuan_history';
const KEY_HISTORY = 'history';
const MAX_HISTORY = 200;

/**
 * 历史浏览记录（持久化于用户首选项）。
 * 进入壁纸详情页时记录：同一 id 去重并置顶，按时间倒序（最新在前）排列，超量截断。
 */
export class HistoryStore {
  private static instance: HistoryStore | undefined;
  private prefs: preferences.Preferences | undefined;
  private items: HistoryEntry[] = [];

  static getInstance(): HistoryStore {
    if (!HistoryStore.instance) {
      HistoryStore.instance = new HistoryStore();
    }
    return HistoryStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    const raw = this.prefs.getSync(KEY_HISTORY, '') as string;
    if (raw && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as HistoryEntry[];
        if (Array.isArray(parsed)) {
          this.items = parsed;
        }
      } catch (e) {
        this.items = [];
      }
    }
  }

  /** 记录一次浏览：去重、置顶、倒序，超量截断 */
  record(item: WallpaperItem): void {
    if (!item || !item.id) {
      return;
    }
    this.items = this.items.filter(h => h.item.id !== item.id);
    this.items.unshift({ item: item, time: Date.now() });
    if (this.items.length > MAX_HISTORY) {
      this.items = this.items.slice(0, MAX_HISTORY);
    }
    this.flush().catch(() => { });
  }

  /** 返回历史（最新在前） */
  getAll(): HistoryEntry[] {
    return this.items.slice();
  }

  count(): number {
    return this.items.length;
  }

  clear(): void {
    this.items = [];
    this.flush().catch(() => { });
  }

  private async flush(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    try {
      await this.prefs.put(KEY_HISTORY, JSON.stringify(this.items));
      await this.prefs.flush();
    } catch (e) {
      // 持久化失败忽略
    }
  }
}
