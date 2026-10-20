import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UserInfo } from '../model/AuthApi';

const PREF_NAME = 'ciyuan_auth';
const KEY_SESSION = 'session';

/**
 * 登录会话持久化（用户首选项）。
 * 保存 token/用户名/id 等信息，重启后自动恢复登录态。
 */
export class AuthStore {
  private static instance: AuthStore | undefined;
  private prefs: preferences.Preferences | undefined;
  private session: UserInfo | null = null;
  /** 登录态变更监听（设置页、云端收藏页等刷新） */
  private listeners: Array<() => void> = [];

  static getInstance(): AuthStore {
    if (!AuthStore.instance) {
      AuthStore.instance = new AuthStore();
    }
    return AuthStore.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    const raw = this.prefs.getSync(KEY_SESSION, '') as string;
    if (raw && raw.length > 0) {
      try {
        this.session = JSON.parse(raw) as UserInfo;
      } catch (e) {
        this.session = null;
      }
    }
    // 初始化完成后通知一次，让 UI 同步持久化的登录态
    this.notify();
  }

  /** 当前会话（未登录返回 null） */
  getSession(): UserInfo | null {
    return this.session;
  }

  isLoggedIn(): boolean {
    return this.session !== null && this.session.token.length > 0;
  }

  /** 保存登录会话 */
  async saveSession(user: UserInfo): Promise<void> {
    this.session = user;
    await this.flush();
    this.notify();
  }

  /** 退出登录 */
  async clearSession(): Promise<void> {
    this.session = null;
    if (this.prefs) {
      await this.prefs.delete(KEY_SESSION);
      await this.prefs.flush();
    }
    this.notify();
  }

  /** 注册登录态变更监听 */
  onSessionChanged(cb: () => void): void {
    this.listeners.push(cb);
  }

  private notify(): void {
    for (const cb of this.listeners) {
      cb();
    }
  }

  private async flush(): Promise<void> {
    if (!this.prefs) {
      return;
    }
    await this.prefs.put(KEY_SESSION, JSON.stringify(this.session));
    await this.prefs.flush();
  }
}
