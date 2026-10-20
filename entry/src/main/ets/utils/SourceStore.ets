import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CustomSource, BUILTIN_SOURCE_DEFS } from '../model/WallpaperSource';
import { hashString } from './HashUtil';

const PREF_NAME = 'ciyuan_sources';
const KEY_CUSTOM_SOURCES = 'custom_sources';
const KEY_ENABLED_BUILTINS = 'enabled_builtins';

/**
 * 自定义图源持久化工具（用户首选项）。
 * 内置图源（次元壁纸/萌鼠动漫/梦API/Loli/内置精选）通过“启用集合”控制是否参与信息流，
 * 默认仅次元壁纸启用，其余默认不启用（用户可在“壁纸源管理”中勾选）。
 * 自定义图源可自由增删，重启后保留。
 */
export class SourceStore {
  private static instance: SourceStore | undefined;
  private prefs: preferences.Preferences | undefined;
  private sources: CustomSource[] = [];
  /** 已启用的内置图源 id 集合，默认仅次元壁纸 */
  private enabledBuiltins: Set<string> = new Set<string>(['ciyuan']);

  static getInstance(): SourceStore {
    if (!SourceStore.instance) {
      SourceStore.instance = new SourceStore();
    }
    return SourceStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    const raw = this.prefs.getSync(KEY_CUSTOM_SOURCES, '') as string;
    if (raw && raw.length > 0) {
      try {
        this.sources = JSON.parse(raw) as CustomSource[];
      } catch (e) {
        this.sources = [];
      }
    }
    const rawEnabled = this.prefs.getSync(KEY_ENABLED_BUILTINS, '') as string;
    if (rawEnabled && rawEnabled.length > 0) {
      try {
        const arr = JSON.parse(rawEnabled) as string[];
        this.enabledBuiltins = new Set<string>(arr);
      } catch (e) {
        this.enabledBuiltins = new Set<string>(['ciyuan']);
      }
    }
    // 兜底：若持久化的启用集合为空，至少保留次元壁纸，避免无源可用
    if (this.enabledBuiltins.size === 0) {
      this.enabledBuiltins.add('ciyuan');
    }
  }

  /** 已启用的内置图源 id 集合（默认仅次元壁纸） */
  getEnabledBuiltins(): Set<string> {
    return new Set<string>(this.enabledBuiltins);
  }

  /** 判断某内置图源是否启用 */
  isBuiltinEnabled(id: string): boolean {
    return this.enabledBuiltins.has(id);
  }

  /** 设置内置图源启用状态并持久化 */
  async setBuiltinEnabled(id: string, enabled: boolean): Promise<void> {
    const known = BUILTIN_SOURCE_DEFS.some(d => d.id === id);
    if (!known) {
      return;
    }
    if (enabled) {
      this.enabledBuiltins.add(id);
    } else {
      this.enabledBuiltins.delete(id);
    }
    // 至少保留一个启用源，避免信息流空
    if (this.enabledBuiltins.size === 0) {
      this.enabledBuiltins.add('ciyuan');
    }
    await this.flushEnabled();
  }

  private async flushEnabled(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put(KEY_ENABLED_BUILTINS, JSON.stringify(Array.from(this.enabledBuiltins)));
    await this.prefs.flush();
  }

  getAll(): CustomSource[] {
    return this.sources.slice();
  }

  /** 生成自定义图源 id（custom_ + URL 哈希），同一 URL 不重复添加 */
  static idForUrl(url: string): string {
    return `custom_${hashString(url)}`;
  }

  async add(name: string, url: string): Promise<CustomSource> {
    const source: CustomSource = {
      id: SourceStore.idForUrl(url),
      name: name,
      url: url
    };
    if (!this.sources.some(s => s.id === source.id)) {
      this.sources.push(source);
      await this.flush();
    }
    return source;
  }

  async remove(id: string): Promise<void> {
    this.sources = this.sources.filter(s => s.id !== id);
    await this.flush();
  }

  private async flush(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put(KEY_CUSTOM_SOURCES, JSON.stringify(this.sources));
    await this.prefs.flush();
  }
}
