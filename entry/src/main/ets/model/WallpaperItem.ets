/**
 * 壁纸数据模型
 */
export interface WallpaperItem {
  /** 唯一标识（URL 的哈希） */
  id: string;
  /** 原图 URL */
  url: string;
  /** 缩略图 URL（可复用原图） */
  thumbUrl: string;
  /** 来源标识 */
  source: string;
  /** 图片宽度（0 表示未知） */
  width: number;
  /** 图片高度（0 表示未知） */
  height: number;
  /** 标签列表 */
  tags: string[];
  /** 是否为本地预置壁纸 */
  local: boolean;
  /** 本地资源名（local 为 true 时有效） */
  localRes?: string;
  /**
   * 是否为“易变”图源：每次请求同一 URL 都返回不同图片（随机图接口）。
   * true 时网格缩略图与详情页都复用同一份预下载字节渲染，避免“预览与详情不是同一张图”。
   */
  volatile?: boolean;
}

export interface WallpaperCategory {
  id: string;
  name: string;
  /** 该分类对应的数据源 provider id */
  providerId: string;
}
