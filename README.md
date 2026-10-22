# 次元壁纸 · HarmonyOS 版（CiyuanWallpaper for HarmonyOS）

[![Release](https://img.shields.io/github/v/release/shy1658/CiyuanWallpaper?label=%E7%89%88%E6%9C%AC&logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/shy1658/CiyuanWallpaper/total?label=%E4%B8%8B%E8%BD%BD%E9%87%8F&logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases)

> 把 Android 二次元壁纸 App「次元壁纸 / AWSL」（`me.alzz.awsl` v2.11.5）移植到 HarmonyOS 的第三方实现。
> 使用 **ArkTS + ArkUI** 编写，产物是一个可直接 `hdc app install` 安装的 `.hap`。
> 本项目为**技术学习与移植演示**，与次元壁纸/AWSL 官方无任何关联。

- **包名**：`com.ciyuan.wallpaper`
- **目标平台**：HarmonyOS NEXT，`compatibleSdkVersion` = `5.0.0(12)`（**最低 API 12**，兼容 HarmonyOS NEXT 及以上设备）
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
| **保存壁纸** | 详情页「存到本地」，原图字节落盘到 `Download/com.ciyuan.wallpaper/` 独立目录，免申请存储权限 |
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

[![下载 HAP](https://img.shields.io/badge/%E4%B8%8B%E8%BD%BD-CiyuanWallpaper--v2.11.74.hap-0A84FF?logo=github)](https://github.com/shy1658/CiyuanWallpaper/releases/latest)

```bash
# 下载 Release 中的 CiyuanWallpaper-v2.11.74.hap 后，用 hdc 安装（设备需开启开发者模式）
hdc app install CiyuanWallpaper-v2.11.74.hap
```

也可从源码构建后安装 `entry/build/default/outputs/default/entry-default-signed.hap`。
启动后 App 名为「次元壁纸」。壁纸统一通过「存到本地」落盘到 Download 目录，免申请相册写入权限。

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
   第三方不可调用，故原版「设为壁纸」改为「**存到本地**」（原图字节落盘到 Download 目录）。
2. **系统相册无自定义分区。** 第三方应用无法创建图库相册，保存的图片统一进入图库默认图片集合
   （平台限制，非应用缺陷）。
3. **账号体系为只读、且暂不可用。** 见顶部「关于登录」说明。
4. **图片加载链路重写。** 统一走 http 模块字节路径（含协议回退），非 ArkUI Image 组件。

---

## 更新日志

| 版本 | 关键变更 |
|---|---|
| **v2.11.74** | **修复网格预览「偏色」（红蓝通道互换）**：HarmonyOS `PixelMap` 创建接口默认按 **BGRA_8888** 解释输入缓冲区，即使声明 `RGBA_8888` 也可能被底层按 BGRA 处理。此前原生模块用 turbojpeg/libavif 输出 **RGBA** 再声明 `RGBA_8888`，导致 R/B 互换（缩略图偏色，而走系统解码的详情原图正常）。现全链路统一 **BGRA_8888**：turbojpeg `TJPF_BGRA`、libavif `AVIF_RGB_FORMAT_BGRA`、`SetPixelFormat` + 显式 `SetSrcPixelFormat` |
| **v2.11.73** | **修网络超时与原生解码降级**：①`request()` 读取超时 30s→**60s**，并新增 `connectTimeout=15s`（官方源 `kha.g.img.13th.tech` 的 10MB+ 原图在移动网络下 30s 不够，报 `2300028 Operation timeout`）；②**超时/DNS 失败不再换协议重试**——此前超时后仍会 https→http 再试一次，一次点击要等两轮共 60s（日志里同一秒两条相同超时即由此产生）；③原生 `DecodeCore` 增加**去 `desiredSize` 重试**：API 12 部分格式（如 WebP）不支持解码时缩放，带缩放参数会直接失败，现在改为全尺寸解码后用 `OH_PixelmapNative_Scale` 缩放；④原生失败原因带上**阶段与 `Image_ErrorCode`**（如 `core pixelmap ec=7700201`），不再只有笼统的 `core decode failed` |
| **v2.11.72** | **最低 API 降回 12 + 内置原生解码「组合拳」**：①`compatibleSdkVersion`/`targetSdkVersion` 回到 `5.0.0(12)`，兼容更多设备；②新增原生模块 `libimage_decode.so`（NAPI + 异步工作线程）——**AVIF/HEIF 走 libavif + dav1d**、**JPEG（含渐进式）走 libjpeg-turbo**、其余格式（PNG/WebP/GIF/BMP）走 **Image_NativeModule**，专门解码失败时再由 Image_NativeModule 末级兜底；③原生解码失败自动回退 ArkTS `image` 解码，任何机型都不会因原生库异常而白屏；④三个三方库（libavif / libjpeg-turbo / libdav1d）均用 OHOS clang-15 交叉编译为 arm64 并打包进 HAP |
| **v2.11.71** | **修复萌鼠动漫等随机（易变）图源保存提示误报「原图不可用（image load failed）」**：易变源 `thumbUrl === url`（缩略图即原图），原图任务整个跳过、全程无任何错误，但 `obtainBuffer()` 仍把「使用缩略图字节」一律当作降级、并读取了从未被真实错误覆盖的默认占位文案 `image load failed`，导致误报。现仅在「存在真实独立的原图（`hasOriginal`）且它已失败（`originalFailed`）」时才标记降级；易变源直接按保存成功处理。同时把默认 `lastErr` 占位值置空，错误页文案兜底为「网络或解码错误」 |
| **v2.11.70** | **修复「第一次保存失败、第二次才成功」**：等待大原图的时限由 6 秒放宽到 30 秒（20MB 级大图"下载+去混淆+校验+解码"远超 6 秒，被误判为失败；后台任务完成后再按就成功——根因即此）；**XOR 去混淆改按 4 字节字原地运算**，比逐字节快约 4 倍且免一次大缓冲拷贝；**死链快速失败**：HTTP 状态码错误（如 http 567）不再尝试 https→http 换协议重试；修复错误日志主机名重复（`@ host @ host`）；保存回退时按真实原因提示（如「原图已失效（图床死链 http 567），已保存预览图」） |
| **v2.11.69** | **修复部分图源的「单字节 XOR 混淆图片」**：实测某自定义源对图片逐字节异或加密（不同响应 key 不同：`0x54` / `0xA6`），导致 `格式=unknown` + `Decode image header failed`。新增 `deobfuscate()`——利用图片魔数固定这一特性**反推 key 并自校验**（如 WebP 头 `RIFF…WEBP` 共 8 个已知字节），命中即整块还原；仅在格式无法识别时尝试，正常图片零影响。已用两条真实日志字节验证还原出合法 WebP |
| **v2.11.68** | **升级到 API 26（HarmonyOS 26）**：`compatibleSdkVersion`/`targetSdkVersion` 由 `5.0.0(12)` 升至 `26.0.0(26)`（⚠️ 仅支持 HarmonyOS 26 及以上设备），系统 image kit 原生解码 **AVIF/HEIF**——此前 API 12 解不开的格式现在直接可看；解码失败日志对无法识别的格式附带**前 16 字节十六进制**，一眼区分 HTML 错误页与乱码数据 |
| **v2.11.67** | **彻底修复随机图源「所见非所存」**：①新增「按条目 id 只请求一次」机制——网格、详情、保存、收藏列表全部命中同一份已解析字节，易变源（如 `wp.upx8.com/api.php`、萌鼠动漫等随机接口）一张图绝不二次随机；②`getBytes` 增加**在途请求去重**，同一地址并发只下载一次（网格与详情并发拉取同一随机地址时共享结果）；③`Accept` 头去掉 `image/avif` 与 `*/*` 通配，仅声明系统原生支持的 JPEG/PNG/WebP/GIF/BMP——**根因：HarmonyOS API 12 原生解码器不支持 AVIF（AVIF 自 API 26 才支持），旧头诱导 CDN 协商出 AVIF 触发 `Decode image header failed`**；④解码失败日志现在带**真实格式识别**（如 `格式=avif/heif`），一眼看出是 AVIF 还是损坏数据 |
| **v2.11.66** | 进一步堵死「裸错误」：抽出统一 `describeError()`，对任意异常值（标准 Error / 裸 `BusinessError` / 字符串 / 数字 / 空值 / 任意对象）都能打出可读细节，日志永不再出现空信息；下载链路为每条失败带出**出错主机**（如 `@ image.coolapk.com`），一眼定位是哪个图床挂了；截断报错也标注主机 |
| **v2.11.65** | 修复错误日志盲区：网络/解码栈抛出的裸 `BusinessError`（仅含 `code`）原样透传，导致「我的 → 日志」里原图加载失败只显示 `undefined: undefined`。新增 `toError()` 规范化为带 `code` 的标准 Error，`Logger.e` 单独打印 `code=`，真实错误码（如 2300063 超限）不再丢失 |
| **v2.11.64** | 修复「保存到本地」扩展名错误：改按**字节魔数**识别真实格式（JPEG/PNG/GIF/WEBP/BMP/TIFF），解决萌鼠动漫等随机源把预览图存成 `.php` 伪后缀的问题；`User-Agent` 同步升级 |
| **v2.11.63** | 删除「保存到图库」功能（SaveButton 10 秒授权窗口内无法等待大原图下载，易失败）；仅保留「存到本地」；新增**自动错误日志收集**（我的 → 日志，最近 300 条）、**历史浏览记录**（我的 → 历史，按时间倒序）、**关于页**（作者 `@shy1658`、未完全移植声明）；移除相册读写权限 |
| **v2.11.62** | 修复「保存到图库」超时失败（已随 v2.11.63 整功能删除，作为历史记录保留） |
| **v2.11.61** | 修复「换一批」不随机：图源加载后按 Fisher-Yates 洗牌，每次刷新结果不同 |
| **v2.11.6** | 修复大图（>5MB）下载损坏：`request()` 命中 `2300063` 自动切 `requestInStream` 流式下载（128MB 上限） |

> 版本号在 `AppScope/app.json5` 与应用内「关于」页同步维护；原版 Android（`me.alzz.awsl` v2.11.5）版本号不在本项目维护范围内。

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
