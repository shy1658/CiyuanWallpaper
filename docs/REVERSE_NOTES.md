# 原版 App（词源壁纸 / AWSL）逆向笔记

> 目标：搞清 https://www.13th.tech/ 分发的 Android App 的接口协议，评估移植到 HarmonyOS 的可行性。
> 结论：私有 API 带 JNI 签名 + 版本网关，不可稳定绕过；移植版改用公开图源。

> **后续更新（与本笔记早期结论不同，以最新为准）**：后来成功复现了签名算法
> `sign = md5(md5(SALT + pair))`（双 MD5，非 JNI），并用真实接口验证通过——
> `GET /rank/main` 仅需签名即可公开访问，已作为移植版的**默认主图源**拉取真实次元壁纸；
> 登录 / 云端收藏等接口亦按同一签名接入（但受服务端版本网关 / 区域风控影响，暂不稳定，见主 README）。
> 本篇作为**早期存档**保留，记录「一度以为不可行」的过程。

## 1. 获取 APK

官网落地页 `https://www.13th.tech/` 只是下载引导页，真实分发走蒲公英。

```
GET https://www.pgyer.com/app/install/{appKey}
  -> 302
  -> OSS 直链
  -> ciyuan-wallpaper-2.11.5.apk   (19,358,137 bytes, MD5 7ce2f5d174ad3af4c32007bdecaa3b4f)
```

## 2. 静态分析

用 androguard 4.1.4 解析 DEX：

| 项 | 值 |
|---|---|
| 包名 | `me.alzz.awsl` |
| versionName / versionCode | 2.11.5 / 211 |
| minSdk / targetSdk | 24 / 34 |
| UI | Jetpack Compose |
| 权限 | 仅 `android.permission.INTERNET` |
| 原生库 | `libhell.so`（arm64-v8a） |

## 3. JNI 签名定位

smali 中出现：

```
invoke-static {p0}, Lme/alzz/Hell;->native_sign(Ljava/lang/String;)Ljava/lang/String;
```

对应 `libhell.so` 导出 `Java_me_alzz_Hell_native_1sign`。该函数对请求参数做 HMAC/摘要，
服务端校验。**无法在纯 Java 层复现**，逆向 so 的成本高于收益。

## 4. Retrofit 路由表

混淆后的接口类（如 `LV1/H3NnV` = `@GET` 注解宿主）反解出以下路由，统一域名 `api.awsl.13th.tech`：

| 接口类 | 路径 | 用途 |
|---|---|---|
| `RankApi` | `/rank/...` | 排行榜 |
| `WallpaperApi` | `/wallpaper/...` | 壁纸列表 / 详情 |
| `UserApi` | `/user/...` | 登录 / 资料 |
| `UploadApi` | `/upload/...` | 壁纸上传 |
| `VersionApi` | `/version` | 版本检查 |
| `ProApi` | `/pro/...` | 会员订阅 |

请求/响应体为 **Protobuf-lite 3.x**（字段号见 `proto_dump.txt`）。

## 5. 动态验证（失败）

按复现的协议构造请求，全部接口返回：

```json
{"code":-2,"msg":"请升级至最新版"}
```

说明服务端除了签名，还有**版本网关**：即使签名算法复现成功，`versionCode` 不匹配最新版
也会被拒。两个校验叠加，稳定绕过不可行。

## 6. 决策

放弃直连私有 API，改为：

1. 聚合公开二次元图源（随机图 API，返回直图 URL，无签名）
2. 内置 24 张预置壁纸，保证断网可用

功能上保留原版的核心体验（信息流 / 分类 / 收藏 / 详情 / 保存），
去掉账号、上传、会员等强依赖私有 API 的模块。
