import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@ohos.base';

/** 单条日志 */
export interface LogEntry {
  time: number;
  level: string;
  tag: string;
  message: string;
}

const PREF_NAME = 'ciyuan_logs';
const KEY_LOGS = 'logs';
const MAX_LOGS = 300;
const DOMAIN = 0x1234;

/**
 * 自动错误日志收集器（持久化于用户首选项）。
 * - 业务关键路径的 catch 统一调用 Logger.e / w / i 落盘；
 * - EntryAbility 注册 errorManager 全局异常监听，捕获未处理的 JS 异常；
 * - 按时间倒序持久保存最近 MAX_LOGS 条，可在「我的 → 日志」查看与清空。
 */
export class Logger {
  private static instance: Logger | undefined;
  private prefs: preferences.Preferences | undefined;
  private logs: LogEntry[] = [];
  private dirty: boolean = false;
  private flushTimer: number | undefined = undefined;

  static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, PREF_NAME);
    const raw = this.prefs.getSync(KEY_LOGS, '') as string;
    if (raw && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as LogEntry[];
        if (Array.isArray(parsed)) {
          this.logs = parsed;
        }
      } catch (e) {
        this.logs = [];
      }
    }
  }

  static i(tag: string, message: string): void {
    Logger.getInstance().append('INFO', tag, message);
  }

  static w(tag: string, message: string): void {
    Logger.getInstance().append('WARN', tag, message);
  }

  static e(tag: string, message: string, error?: Error): void {
    let msg = message;
    if (error) {
      // 容错：网络/解码栈常抛出裸 BusinessError（只有 code、无 name/message/stack），
      // 若只取 error.name/error.message 会变成 "undefined: undefined"，真实错误码丢失。
      const code = (error as BusinessError).code;
      const name = error.name;
      const emsg = error.message;
      const stack = error.stack;
      if (code !== undefined && code !== null) {
        msg += ` | code=${code}`;
      }
      if ((name !== undefined && name.length > 0) || (emsg !== undefined && emsg.length > 0)) {
        msg += ` | ${name ?? ''}: ${emsg ?? ''}`;
      }
      if (stack !== undefined && stack.length > 0) {
        msg += ` | ${stack}`;
      }
    }
    Logger.getInstance().append('ERROR', tag, msg);
  }

  static fatal(tag: string, message: string): void {
    Logger.getInstance().append('FATAL', tag, message);
  }

  private append(level: string, tag: string, message: string): void {
    const entry: LogEntry = { time: Date.now(), level, tag, message };
    this.logs.push(entry);
    if (this.logs.length > MAX_LOGS) {
      this.logs = this.logs.slice(this.logs.length - MAX_LOGS);
    }
    this.dirty = true;
    hilog.info(DOMAIN, 'CiyuanLogger', '%{public}s/%{public}s: %{public}s', level, tag, message);
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.flushTimer !== undefined) {
      return;
    }
    this.flushTimer = setTimeout(() => {
      this.flushTimer = undefined;
      this.flush().catch(() => { });
    }, 800);
  }

  private async flush(): Promise<void> {
    if (!this.prefs || !this.dirty) {
      return;
    }
    try {
      await this.prefs.put(KEY_LOGS, JSON.stringify(this.logs));
      await this.prefs.flush();
      this.dirty = false;
    } catch (e) {
      // 持久化失败不影响内存日志
    }
  }

  /** 返回日志（最新在前） */
  getAll(): LogEntry[] {
    return this.logs.slice().reverse();
  }

  count(): number {
    return this.logs.length;
  }

  clear(): void {
    this.logs = [];
    this.dirty = true;
    this.flush().catch(() => { });
  }
}
