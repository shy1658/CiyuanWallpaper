import { http } from '@kit.NetworkKit';
import { md5Hex } from '../utils/Md5Util';

/**
 * 原版次元壁纸（13th.tech）账号体系 API 客户端。
 *
 * 请求签名规则（逆向自原版 me.alzz.awsl v2.11.5）：
 *   sign = md5(md5(SALT + pair))
 *   pair = sorted(set([请求参数 k=v（原始值）] + [t=<毫秒时间戳>])).join('&')
 * 请求头携带 t（毫秒时间戳）与 sign；POST 表单值为 URL 编码，
 * 签名对中的参数值使用原始值（不编码）。
 */
const BASE_URL = 'https://api.awsl.13th.tech';
const SALT = 'xS544RXNm0P4JVLHIEsTqJNzDbZhiLjr';
/** 客户端版本号（原版 me.alzz.awsl v2.11.5），用于服务端版本校验接口（如收藏） */
const APP_VERSION = '2.11.5';

/** 用户信息（登录/用户信息接口返回实体） */
export interface UserInfo {
  id: string;
  token: string;
  username: string;
  email: string;
  phone: string;
  isPro: boolean;
}

/** 云端收藏分组 */
export interface LoveGroup {
  name: string;
  count: number;
  thumbUrl: string;
}

/** 云端壁纸（官方 Wallpaper 实体的投影） */
export interface CloudWallpaper {
  id: string;
  url: string;
  thumbUrl: string;
  author: string;
  width: number;
  height: number;
  love: number;
  tags: string[];
}

/** 收藏标记查询结果 */
export interface LoveMark {
  wid: string;
  marked: boolean;
  createTime: number;
}

/** 收藏列表响应包装（w/love 返回：{ total, loves:[...], groups:[...] }） */
export interface LoveListResult {
  total: number;
  loves: CloudWallpaper[];
  groups: LoveGroup[];
}

/** 服务端统一响应包装 */
interface ServerResult<T> {
  code: number;
  msg: string;
  data: T | null;
}

/** 构造签名对：sorted(set(pairs)).join('&') */
function buildPair(pairs: string[]): string {
  const set = new Set<string>();
  for (const p of pairs) {
    set.add(p);
  }
  const arr = Array.from(set).sort();
  return arr.join('&');
}

/** 计算请求签名 */
function signOf(pairs: string[]): string {
  return md5Hex(md5Hex(SALT + buildPair(pairs)));
}

/** 当前毫秒时间戳字符串 */
function nowMillis(): string {
  return String(Date.now());
}

/** 发起 GET 请求并解析统一响应 */
async function getJson<T>(path: string, params: Array<[string, string]>): Promise<ServerResult<T>> {
  const millis = nowMillis();
  const pairs: string[] = [];
  const encoded: string[] = [];
  for (let i = 0; i < params.length; i++) {
    const k = params[i][0];
    const v = params[i][1];
    pairs.push(`${k}=${v}`);
    encoded.push(`${k}=${encodeURIComponent(v)}`);
  }
  pairs.push(`t=${millis}`);
  const url = `${BASE_URL}${path}?${encoded.join('&')}`;
  const request = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: { 't': millis, 'sign': signOf(pairs) },
      readTimeout: 30000
    };
    const resp = await request.request(url, opts);
    if (resp.responseCode !== 200) {
      throw new Error(`http ${resp.responseCode}`);
    }
    return JSON.parse(resp.result as string) as ServerResult<T>;
  } finally {
    request.destroy();
  }
}

/** 发起 POST 表单请求并解析统一响应 */
async function postFormJson<T>(path: string, form: Array<[string, string]>,
  query: Array<[string, string]>): Promise<ServerResult<T>> {
  const millis = nowMillis();
  const pairs: string[] = [];
  const encodedForm: string[] = [];
  for (let i = 0; i < form.length; i++) {
    const k = form[i][0];
    const v = form[i][1];
    pairs.push(`${k}=${v}`);
    encodedForm.push(`${k}=${encodeURIComponent(v)}`);
  }
  const encodedQuery: string[] = [];
  for (let i = 0; i < query.length; i++) {
    const k = query[i][0];
    const v = query[i][1];
    pairs.push(`${k}=${v}`);
    encodedQuery.push(`${k}=${encodeURIComponent(v)}`);
  }
  pairs.push(`t=${millis}`);
  let url = `${BASE_URL}${path}`;
  if (encodedQuery.length > 0) {
    url += `?${encodedQuery.join('&')}`;
  }
  const request = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        't': millis,
        'sign': signOf(pairs)
      },
      extraData: encodedForm.join('&'),
      readTimeout: 20000
    };
    const resp = await request.request(url, opts);
    if (resp.responseCode !== 200) {
      throw new Error(`http ${resp.responseCode}`);
    }
    return JSON.parse(resp.result as string) as ServerResult<T>;
  } finally {
    request.destroy();
  }
}

/** 业务错误：服务端返回 code != 0 */
export class ApiError extends Error {
  public code: number;
  constructor(code: number, msg: string) {
    super(msg.length > 0 ? msg : `服务端错误 code=${code}`);
    this.code = code;
  }
}

function unwrap<T>(result: ServerResult<T>): T {
  if (result.code !== 0) {
    throw new ApiError(result.code, result.msg);
  }
  return result.data as T;
}

/**
 * 账号体系 API。
 */
export class AuthApi {
  /** 登录：POST /u/login（表单 account/pwd） */
  static async login(account: string, pwd: string): Promise<UserInfo> {
    const result = await postFormJson<UserInfo>('/u/login',
      [['account', account], ['pwd', pwd]], []);
    return unwrap(result);
  }

  /** 查询当前用户信息：GET /u?token= */
  static async getUserInfo(token: string): Promise<UserInfo> {
    const result = await getJson<UserInfo>('/u', [['token', token]]);
    return unwrap(result);
  }

  /** 云端收藏分组：GET /w/love/group?token= */
  static async getLoveGroups(token: string): Promise<LoveGroup[]> {
    const result = await getJson<LoveGroup[]>('/w/love/group', [['token', token]]);
    return unwrap(result) ?? [];
  }

  /** 云端收藏列表：GET /w/love?token&group&offset&v=
   *  注意响应为包装对象 { total, loves:[...], groups:[...] }，收藏在 loves 字段；
   *  v 传真实客户端版本，避免服务端返回“请升级至最新版”。 */
  static async getLoves(token: string, group: string, offset: number): Promise<CloudWallpaper[]> {
    const result = await getJson<LoveListResult>('/w/love',
      [['token', token], ['group', group], ['offset', String(offset)], ['v', APP_VERSION]]);
    const data = unwrap(result);
    return data?.loves ?? [];
  }

  /** 原版主信息流（官方真实壁纸，稳定直链）：GET /rank/main（签名即可，无需登录） */
  static async getRankMain(): Promise<CloudWallpaper[]> {
    const result = await getJson<CloudWallpaper[]>('/rank/main', []);
    return unwrap(result) ?? [];
  }

  /** 我的上传：GET /w/upload?token&page= */
  static async getUploads(token: string, page: number): Promise<CloudWallpaper[]> {
    const result = await getJson<CloudWallpaper[]>('/w/upload',
      [['token', token], ['page', String(page)]]);
    return unwrap(result) ?? [];
  }

  /** 查询壁纸收藏状态：GET /w/love/mark?token&wid= */
  static async getLoveMark(token: string, wid: string): Promise<LoveMark> {
    const result = await getJson<LoveMark>('/w/love/mark',
      [['token', token], ['wid', wid]]);
    return unwrap(result);
  }
}
