# 次元壁纸 · HarmonyOS 版（CiyuanWallpaper for HarmonyOS）

[![Release](https://img.shields.io/github/v/release/shy1658/CiyuanWallpaper?label=%E7%89%88%E6%9C%AC&logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/shy1658/CiyuanWallpaper/total?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases)

> 把 Android 二次元壁纸 App「次元壁纸 / AWSL」（`me.alzz.awsl` v2.11.5）移植到 HarmonyOS 的第三方实现。
> 使用 **ArkTS + ArkUI** 编写，产物是一个可直接 `hdc app install` 安装的 `.hap`。
> 本项目为**技术学习与移植演示**，与次元壁纸/AWSL 官方无任何关联。

- **包名**：`com.ciyuan.wallpaper`
- **目标平台**：HarmonyOS NEXT，`compatibleSdkVersion` = `5.0.0(12)`（API 12 及以上）
- **默认主图源**：原版官方源 `rank/main`（真实次元壁纸，B 站图床稳定直链）

---

## ⚠️ 关于「登录 / 云端收藏」

App 内保留了原版账号体系的登录与云端收藏入口，但**目前不建议使用**：

- 原版服务端带有**版本网关 + 区域风控**，部分网络/账号下登录与云端接口会统一返回
  「请升级至最新版」，无法稳定访问；
- 该功能**不影响核心的壁纸浏览、下载与本地收藏**，可完全忽略；
- 本地收藏（`FavoritesStore`）独立于账号体系，断网亦可正常使用。

---

## 基本功能

| 模块 | 说明 |
|---|---|
| **首页信息流** | 网格瀑布流浏览壁纸，滚动到底自动加载下一页，支持「换一批」刷新 |
| **分类浏览** | 按图源 chip 筛选（聚合 + 各已启用源 + 自定义源，动态生成） |
| **壁纸详情** | 全屏大图 + 双指缩放预览 |
| **下载壁纸** | 保存原图到系统图库（SaveButton 安全控件，免申请存储权限） |
| **存到本地** | 落盘到 `Download/com.ciyuan.wallpaper/` 独立目录 |
| **本地收藏** | 收藏夹持久化，断网可用 |
| **壁纸源管理** | 内置源**逐项开关**（默认仅「次元壁纸」启用）+ **自定义图源自由添加/删除**，持久化并热生效 |
| **预置壁纸** | 24 张内置二次元壁纸，断网可浏览 |
| **设置页** | 账号行、云端入口、壁纸源入口、清空缓存 |

**「所见即所存」**：预览与保存共用同一份预下载字节（解码为 PixelMap 渲染），
保证点开大图看到的、和最终保存下来的，是同一张图——不会出现「预览与保存不是同一张」。

---

## 图源

启动后默认只启用**次元壁纸（官方源）**，其余内置源默认关闭，可在「设置 → 壁纸源管理」逐项勾选。

| 图源 | 地址 / 说明 | 默认启用 |
|---|---|---|
| **次元壁纸（官方源，置顶）** | 原版签名接口 `GET /rank/main`，返回真实次元壁纸稳定直链（`i0.hdslb.com`） | ✅ 是 |
| 萌鼠动漫 | `https://dmoe.cc/random.php`（随机图） | ❌ 否 |
| 梦API | `https://api.mtyqx.cn/api/random.php`（随机图） | ❌ 否 |
| Loli图库 | `https://www.loliapi.com/acg/pc/`（随机图） | ❌ 否 |
| 内置精选 | 内置 24 张 `resources/base/media/wp_*.jpg`，断网可浏览 | ❌ 否 |

- **自定义图源**：在「设置 → 壁纸源管理」填写任意**直接返回图片**的 API 地址（如 `https://example.com/random.php`）即可新增，持久化保存、实时生效。
- **随机源一致性**：随机图接口每次请求同一 URL 会返回不同图片，App 将其标记为「易变源」，
  网格缩略图与详情页复用同一份按 URL 缓存的字节，保证预览/详情/保存为同一张。
- **图片加载**：所有网络图片统一经 http 模块下载字节 → 解码 PixelMap 渲染，并带 https↔http 回退，
  规避 ArkUI `Image(URL)` 组件加载图床直链的不稳定性。

---

## 安装

**直接下载安装包**（推荐，免构建）：

[![下载 HAP](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-CiyuanWallpaper--v2.11.64.hap-0A84FF?logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases/latest)

```bash
# 下载 Release 中的 CiyuanWallpaper-v2.11.64.hap 后，用 hdc 安装（设备需开启开发者模式）
hdc app install CiyuanWallpaper-v2.11.64.hap
```

也可从源码构建后安装 `entry/build/default/outputs/default/entry-default-signed.hap`。
启动后 App 名为「次元壁纸」。首次保存壁纸可能弹窗申请相册写入权限。

---

## 从源码构建

依赖：HarmonyOS Command Line Tools + Node.js（≥ 18）。

```bash
# 1. 配置签名：复制模板并按需填写（密码需为 hvigor 接受的加密材料）
cp build-profile.json5.example build-profile.json5
#    并准备 signing/ 下的证书与 Profile（本地调试证书即可，见下）

# 2. 在 local.properties 指定 SDK 路径
echo "sdk.dir=/path/to/command-line-tools/sdk" > local.properties

# 3. 一键构建（编译 + 打包 + 签名）
bash build.sh
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`。

> 仓库中的 `build-profile.json5`（含签名密码）与 `signing/`（密钥证书）已按**本地敏感文件**处理，
> 不会入库；请以 `build-profile.json5.example` 为模板、用**自建的本地调试证书**填充。
> 上架 AppGallery 需改用华为开发者联盟的正式签名材料。

---

## 与原生/原版的差异

1. **下载而非直设壁纸。** HarmonyOS 的 `WallpaperKit.setWallpaper` 自 API 9 起为 systemapi，
   第三方不可调用，故原版「设为壁纸」改为「**下载壁纸**」（SaveButton 存图库 / 存到本地目录）。
2. **系统相册无自定义分区。** 第三方应用无法创建图库相册，保存的图片统一进入图库默认图片集合
   （平台限制，非应用缺陷）。
3. **账号体系为只读、且暂不可用。** 见顶部「关于登录」说明。
4. **图片加载链路重写。** 统一走 http 模块字节路径（含协议回退），非 ArkUI Image 组件。

---

## 工程结构

```
CiyuanWallpaper/
├── AppScope/app.json5            # 应用级配置（bundleName / 版本 / API 级别）
├── build-profile.json5.example   # 构建+签名配置模板（真实文件含密码，已 gitignore）
├── hvigorfile.ts / oh-package.json5 / build.sh
├── docs/REVERSE_NOTES.md         # 原版 App 逆向笔记（存档）
└── entry/src/main/
    ├── module.json5              # 权限 / abilities / pages
    ├── resources/base/           # 字符串 / 颜色 / 图标 / 24 张预置壁纸
    └── ets/
        ├── entryability/EntryAbility.ets
        ├── model/                # WallpaperItem / WallpaperSource（图源）/ AuthApi（签名客户端）
        ├── viewmodel/            # WallpaperStore（全局状态 + 图源管理）
        ├── utils/                # FavoritesStore / ImageSaveUtil / ImageByteCache / Md5Util
        │                         # AuthStore / SourceStore / HashUtil
        ├── common/               # WallpaperGrid / WallpaperCard / NetImage
        └── pages/                # Index / HomeFeed / Category / Explore / Favorite /
                                  # Settings / Detail / Login / CloudLove / SourceManage
```

---

## 许可与声明

- 本项目为**技术学习与移植演示**，与麦当劳、次元壁纸/AWSL 官方无任何关联。
- 内置壁纸来自公开图源，版权归原作者所有；如需商用请替换为自有素材。
- 逆向过程存档见 [`docs/REVERSE_NOTES.md`](docs/REVERSE_NOTES.md)。
