import { WallpaperItem } from './WallpaperItem';
import { hashString } from '../utils/HashUtil';
import { AuthApi, CloudWallpaper } from './AuthApi';

/**
 * 在线壁纸源接口。
 * 每个数据源实现 fetch 方法，返回一批壁纸条目。
 */
export interface WallpaperProvider {
  id: string;
  name: string;
  /** 是否为“易变”图源：每次请求同一 URL 都返回不同图片（随机图接口） */
  volatile?: boolean;
  /** 获取一批壁纸，count 为期望张数 */
  fetch(count: number): Promise<WallpaperItem[]>;
  /** 可选：刷新时重置分页游标（有状态的分页源需实现） */
  reset?(): void;
}

/** 内置图源定义（id 与展示名），供 SourceStore 启用集合与 UI 共用 */
export interface BuiltinSourceDef {
  id: string;
  name: string;
}

/**
 * 内置图源注册表。顺序即分类页/管理页展示顺序。
 * 其中次元壁纸（ciyuan）为原版官方源，默认启用；其余内置源默认不启用，由用户在“壁纸源管理”中勾选。
 */
export const BUILTIN_SOURCE_DEFS: BuiltinSourceDef[] = [
  { id: 'ciyuan', name: '次元壁纸' },
  { id: 'dmoe', name: '萌鼠动漫' },
  { id: 'mtyqx', name: '梦API' },
  { id: 'loli', name: 'Loli图库' },
  { id: 'local', name: '内置精选' }
];

/** 用户自定义图源（持久化于用户首选项） */
export interface CustomSource {
  /** 唯一标识（custom_ + URL 哈希） */
  id: string;
  /** 用户设置的显示名称 */
  name: string;
  /** 图源 API 地址（每次请求附加随机参数防缓存） */
  url: string;
}

/** 由自定义图源创建 provider（URL 后自动附加 _r 随机参数） */
export function createCustomProvider(source: CustomSource): WallpaperProvider {
  return new CustomProvider(source);
}

let nonceSeed: number = 0;

function makeItem(url: string, source: string, width: number, height: number, volatile: boolean): WallpaperItem {
  // 随机图接口每次请求都返回同一 URL，需要附加 nonce 保证 id 唯一
  nonceSeed++;
  const id = hashString(`${url}#${Date.now()}#${nonceSeed}`);
  return {
    id: id,
    url: url,
    thumbUrl: url,
    source: source,
    width: width,
    height: height,
    tags: [],
    local: false,
    volatile: volatile
  };
}

/**
 * 原版次元壁纸官方源（默认主源，置顶）。
 * 调用原版签名接口 GET /rank/main 获取真实次元壁纸（稳定直链，
 * 指向 B 站图床 i0.hdslb.com），与原版 App 展示的壁纸一致。
 * 一次拉取全量后本地分页，保证“上拉加载更多”稳定可用，
 * 且每条壁纸的 url/thumbUrl 为固定直链，下载保存与预览必然是同一张图。
 */
export class CiyuanProvider implements WallpaperProvider {
  id = 'ciyuan';
  name = '次元壁纸';
  private all: WallpaperItem[] = [];
  private loaded: boolean = false;
  private cursor: number = 0;

  async fetch(count: number): Promise<WallpaperItem[]> {
    if (!this.loaded) {
      await this.loadAll();
    }
    if (this.cursor >= this.all.length) {
      return [];
    }
    const slice = this.all.slice(this.cursor, this.cursor + count);
    this.cursor += slice.length;
    return slice;
  }

  reset(): void {
    this.cursor = 0;
  }

  private async loadAll(): Promise<void> {
    const list: CloudWallpaper[] = await AuthApi.getRankMain();
    this.all = list.map((w: CloudWallpaper) => CiyuanProvider.toItem(w));
    this.loaded = true;
  }

  /** 把明文 http 直链升级为 https（hdslb 等图床支持 https，规避鸿蒙默认禁止明文 HTTP 流量） */
  private static toHttps(u: string): string {
    if (u && u.startsWith('http://')) {
      return 'https://' + u.substring('http://'.length);
    }
    return u;
  }

  private static toItem(w: CloudWallpaper): WallpaperItem {
    const tags: string[] = [];
    if (w.tags) {
      for (const t of w.tags) {
        if (t && t.length > 0) {
          tags.push(t);
        }
      }
    }
    if (tags.length === 0 && w.author && w.author.length > 0) {
      tags.push(w.author);
    }
    const url = CiyuanProvider.toHttps(w.url);
    const thumbUrl = CiyuanProvider.toHttps(w.thumbUrl && w.thumbUrl.length > 0 ? w.thumbUrl : w.url);
    return {
      // 使用官方稳定 id，便于去重与云端收藏对应
      id: w.id,
      url: url,
      thumbUrl: thumbUrl,
      source: '次元壁纸',
      width: w.width,
      height: w.height,
      tags: tags,
      local: false
    };
  }
}

/** 萌鼠随机二次元图（随机源：每次请求返回不同图，需按字节缓存） */
class DmoeProvider implements WallpaperProvider {
  id = 'dmoe';
  name = '萌鼠动漫';
  volatile = true;

  async fetch(count: number): Promise<WallpaperItem[]> {
    const items: WallpaperItem[] = [];
    for (let i = 0; i < count; i++) {
      items.push(makeItem(`https://www.dmoe.cc/random.php?_r=${Math.random()}`, this.name, 0, 0, true));
    }
    return items;
  }
}

/** 梦 tyq 随机图（随机源） */
class MtyqxProvider implements WallpaperProvider {
  id = 'mtyqx';
  name = '梦API';
  volatile = true;

  async fetch(count: number): Promise<WallpaperItem[]> {
    const items: WallpaperItem[] = [];
    for (let i = 0; i < count; i++) {
      items.push(makeItem(`https://api.mtyqx.cn/api/random.php?_r=${Math.random()}`, this.name, 0, 0, true));
    }
    return items;
  }
}

/** Loli 随机图（PC 端二次元，随机源） */
class LoliProvider implements WallpaperProvider {
  id = 'loli';
  name = 'Loli图库';
  volatile = true;

  async fetch(count: number): Promise<WallpaperItem[]> {
    const items: WallpaperItem[] = [];
    for (let i = 0; i < count; i++) {
      items.push(makeItem(`https://www.loliapi.com/acg/pc/?_r=${Math.random()}`, this.name, 0, 0, true));
    }
    return items;
  }
}

/** 用户自定义图源：直接请求用户提供的 API 地址（按随机参数请求，视为易变源） */
export class CustomProvider implements WallpaperProvider {
  id: string;
  name: string;
  volatile = true;
  private url: string;

  constructor(source: CustomSource) {
    this.id = source.id;
    this.name = source.name;
    this.url = source.url;
  }

  async fetch(count: number): Promise<WallpaperItem[]> {
    const items: WallpaperItem[] = [];
    const sep = this.url.includes('?') ? '&' : '?';
    for (let i = 0; i < count; i++) {
      const url = `${this.url}${sep}_r=${Math.random()}`;
      items.push(makeItem(url, this.name, 0, 0, true));
    }
    return items;
  }
}

/** 本地预置壁纸源（离线可用） */
export class LocalProvider implements WallpaperProvider {
  id = 'local';
  name = '内置精选';
  private resources: string[] = [
    'wp_1', 'wp_2', 'wp_3', 'wp_4', 'wp_5', 'wp_6',
    'wp_7', 'wp_8', 'wp_9', 'wp_10', 'wp_11', 'wp_12',
    'wp_13', 'wp_14', 'wp_15', 'wp_16', 'wp_17', 'wp_18',
    'wp_19', 'wp_20', 'wp_21', 'wp_22', 'wp_23', 'wp_24'
  ];

  async fetch(count: number): Promise<WallpaperItem[]> {
    const items: WallpaperItem[] = [];
    const shuffled = this.resources.slice().sort(() => Math.random() - 0.5);
    const picked = shuffled.slice(0, Math.min(count, shuffled.length));
    for (const res of picked) {
      items.push({
        id: 'local_' + res,
        url: '',
        thumbUrl: '',
        source: this.name,
        width: 0,
        height: 0,
        tags: ['精选'],
        local: true,
        localRes: res
      });
    }
    return items;
  }

  reset(): void {
    // 预置资源固定，无需重置分页
  }
}

/** 聚合源：并发调用多个 provider，合并结果 */
export class AggregateProvider implements WallpaperProvider {
  id = 'aggregate';
  name = '全部源';
  private providers: WallpaperProvider[];

  constructor(providers: WallpaperProvider[]) {
    this.providers = providers;
  }

  async fetch(count: number): Promise<WallpaperItem[]> {
    const perProvider = Math.max(1, Math.ceil(count / this.providers.length));
    const results = await Promise.allSettled(this.providers.map(p => p.fetch(perProvider)));
    const items: WallpaperItem[] = [];
    for (const r of results) {
      if (r.status === 'fulfilled') {
        for (const item of r.value) {
          items.push(item);
        }
      }
    }
    // 打乱顺序，混合展示
    return items.sort(() => Math.random() - 0.5);
  }

  reset(): void {
    for (const p of this.providers) {
      if (p.reset) {
        p.reset();
      }
    }
  }
}

/**
 * 默认图源列表。
 * 顺序即分类页 chips 顺序：次元壁纸（原版官方源，默认主源）置顶，
 * 其后为附加随机源与内置预置；用户自定义源由 WallpaperStore 另行拼接。
 */
export function createDefaultProviders(): WallpaperProvider[] {
  return [
    new CiyuanProvider(),
    new DmoeProvider(),
    new MtyqxProvider(),
    new LoliProvider(),
    new LocalProvider()
  ];
}
