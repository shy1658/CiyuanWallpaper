import { common } from '@kit.AbilityKit';
import { WallpaperItem } from '../model/WallpaperItem';
import {
  WallpaperProvider,
  AggregateProvider,
  CustomSource,
  createDefaultProviders,
  createCustomProvider
} from '../model/WallpaperSource';
import { FavoritesStore } from '../utils/FavoritesStore';
import { SourceStore } from '../utils/SourceStore';

const PAGE_SIZE = 20;

/**
 * 全局壁纸数据仓库（单例）。
 * 管理壁纸流数据、加载状态与收藏状态。
 * 图源 = 5 个内置默认源 + 用户自定义源（持久化，可增删）。
 */
export class WallpaperStore {
  private static instance: WallpaperStore | undefined;
  private aggregate: AggregateProvider;
  private currentProviderId: string = 'ciyuan';
  private providers: WallpaperProvider[];
  private customSources: CustomSource[] = [];
  private initialized: boolean = false;
  /** 图源列表变更监听（分类页 chips 刷新等） */
  private listeners: Array<() => void> = [];

  /** 当前列表数据 */
  items: WallpaperItem[] = [];
  /** 是否正在加载 */
  loading: boolean = false;
  /** 是否已加载完（当前源无更多内容） */
  finished: boolean = false;

  private constructor() {
    this.providers = createDefaultProviders();
    this.aggregate = new AggregateProvider(this.providers);
  }

  static getInstance(): WallpaperStore {
    if (!WallpaperStore.instance) {
      WallpaperStore.instance = new WallpaperStore();
    }
    return WallpaperStore.instance;
  }

  /** 初始化（EntryAbility 调用）：加载持久化的自定义图源与内置源启用集合 */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    await SourceStore.getInstance().init(context);
    this.customSources = SourceStore.getInstance().getAll();
    this.rebuildProviders();
  }

  /** 用“已启用的内置源 + 自定义源”重建 provider 列表与聚合源，并通知监听者 */
  private rebuildProviders(): void {
    const enabled = SourceStore.getInstance().getEnabledBuiltins();
    const customs: WallpaperProvider[] = this.customSources.map(createCustomProvider);
    const builtins: WallpaperProvider[] = createDefaultProviders().filter(p => enabled.has(p.id));
    this.providers = builtins.concat(customs);
    this.aggregate = new AggregateProvider(this.providers);
    // 校准当前源：若当前源已不在可用列表（被关闭）或为空，回退到第一个可用源
    const valid = this.providers.some(p => p.id === this.currentProviderId);
    if (!valid && this.currentProviderId !== 'aggregate') {
      this.currentProviderId = this.providers.length > 0 ? this.providers[0].id : 'aggregate';
    }
    for (const cb of this.listeners) {
      cb();
    }
  }

  /** 切换内置图源的启用状态（持久化 + 热生效 + 校准当前源） */
  async setBuiltinEnabled(context: common.UIAbilityContext, id: string, enabled: boolean): Promise<void> {
    await SourceStore.getInstance().init(context);
    await SourceStore.getInstance().setBuiltinEnabled(id, enabled);
    this.rebuildProviders();
  }

  /** 注册图源变更监听 */
  onProvidersChanged(cb: () => void): void {
    this.listeners.push(cb);
  }

  /** 新增自定义图源（持久化并热生效） */
  async addCustomSource(context: common.UIAbilityContext, name: string, url: string): Promise<void> {
    await SourceStore.getInstance().init(context);
    await SourceStore.getInstance().add(name, url);
    this.customSources = SourceStore.getInstance().getAll();
    this.rebuildProviders();
  }

  /** 删除自定义图源（持久化并热生效） */
  async removeCustomSource(context: common.UIAbilityContext, id: string): Promise<void> {
    await SourceStore.getInstance().init(context);
    await SourceStore.getInstance().remove(id);
    this.customSources = SourceStore.getInstance().getAll();
    this.rebuildProviders();
  }

  /** 当前自定义图源列表 */
  getCustomSources(): CustomSource[] {
    return this.customSources.slice();
  }

  /** 切换数据源（同时重置目标源与聚合源的分页游标） */
  setProvider(id: string): void {
    this.currentProviderId = id;
    this.items = [];
    this.finished = false;
    this.resetProviders();
  }

  /** 重置当前源与聚合源的分页游标（刷新/切换时调用，避免 Ciyuan 等缓存源跳过首页） */
  private resetProviders(): void {
    const current = this.providers.find(p => p.id === this.currentProviderId);
    if (current && current.reset) {
      current.reset();
    }
    if (this.aggregate.reset) {
      this.aggregate.reset();
    }
  }

  getProviderId(): string {
    return this.currentProviderId;
  }

  getProviderList(): WallpaperProvider[] {
    return this.providers;
  }

  /** 加载一批壁纸 */
  async loadMore(): Promise<WallpaperItem[]> {
    if (this.loading || this.finished) {
      return [];
    }
    this.loading = true;
    try {
      const provider = this.providers.find(p => p.id === this.currentProviderId) ?? this.aggregate;
      const fresh = await provider.fetch(PAGE_SIZE);
      // 去重
      const existingIds = new Set(this.items.map(i => i.id));
      const deduped = fresh.filter(i => !existingIds.has(i.id));
      this.items = this.items.concat(deduped);
      return deduped;
    } finally {
      this.loading = false;
    }
  }

  /** 刷新（重新拉取） */
  async refresh(): Promise<WallpaperItem[]> {
    this.items = [];
    this.finished = false;
    this.resetProviders();
    return await this.loadMore();
  }

  isFavorite(id: string): boolean {
    return FavoritesStore.getInstance().isFavorite(id);
  }

  async toggleFavorite(item: WallpaperItem): Promise<boolean> {
    return await FavoritesStore.getInstance().toggle(item);
  }

  getFavorites(): WallpaperItem[] {
    return FavoritesStore.getInstance().getAll();
  }
}
