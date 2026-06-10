# 飞牛TV 弹幕版 · Flutter 跨平台客户端 🎯

> 基于飞牛影视 (FnOS) API 的第三方跨平台客户端，支持弹幕、自动连播、多平台运行。

---

## 📸 功能特性

| 功能 | 说明 |
|------|------|
| **弹幕支持** | 集成弹幕 API，自动匹配番剧弹幕，支持滚动/顶部/底部三种弹幕模式 |
| **继续观看** | 记录播放进度，首页快速续播，进度条可视化 |
| **剧集自动连播** | 播放完成后自动播放下一集 |
| **倍速播放** | 支持 0.5x ~ 2.0x 播放速度 |
| **画质切换** | 支持直链/代理模式，多画质选择 |
| **锁定模式** | 锁定后隐藏控制栏，防止误触 |
| **弹幕高度自定义** | 不透明度、字号、显示区域、速度、密度、描边全部可调 |
| **深色主题** | Material 3 暗色主题，护眼舒适 |
| **跨平台** | Android / iOS / macOS / Windows / Linux / Web 全平台支持 |

---

## 🛠 技术栈

| 层级 | 技术 |
|------|------|
| **框架** | Flutter 3.x + Dart 3.x |
| **状态管理** | Provider |
| **网络请求** | Dio + 自定义 Authx 签名拦截器 |
| **视频播放** | video_player + chewie |
| **弹幕渲染** | CustomPainter 自绘引擎 |
| **图片缓存** | cached_network_image |
| **本地存储** | shared_preferences |
| **CI/CD** | GitHub Actions |

---

## 📦 项目结构

```
lib/
├── main.dart                           # 应用入口
├── models/                             # 数据模型
│   ├── api_response.dart               #   通用 API 响应
│   ├── danmu_comment.dart              #   弹幕评论
│   ├── media_item.dart                 #   媒体库条目
│   ├── play_info.dart                  #   播放信息
│   ├── play_list_item.dart             #   播放列表项
│   ├── stream_response.dart            #   流媒体信息
│   └── watch_record.dart               #   观看记录
├── services/                           # 网络服务
│   ├── api_client.dart                 #   API 客户端 (Dio + Authx)
│   └── auth_utils.dart                 #   签名工具 (MD5)
├── providers/                          # 状态管理
│   └── app_state.dart                  #   全局应用状态
├── screens/                            # 页面
│   ├── login_screen.dart               #   登录页
│   ├── home_screen.dart                #   首页 (概览/媒体库/浏览)
│   ├── player_screen.dart              #   播放器页
│   └── settings_screen.dart            #   设置页
├── widgets/                            # 组件
│   ├── media_card.dart                 #   媒体卡片
│   ├── continue_watching_card.dart     #   续播卡片
│   ├── danmu_overlay.dart              #   弹幕覆盖层
│   └── player_controls.dart            #   播放控制栏
└── utils/                              # 工具
    ├── theme.dart                      #   主题定义
    └── format.dart                     #   格式化工具
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- Android Studio / Xcode（按目标平台）

### 本地运行

```bash
# 1. 克隆项目
git clone git@github.com:jimboo7339/fntv_danmu_all.git
cd fntv_danmu_all

# 2. 安装依赖
flutter pub get

# 3. 运行（选择你的目标平台）
flutter run                    # 默认设备
flutter run -d chrome          # Web
flutter run -d macos           # macOS
flutter run -d windows         # Windows
flutter run -d linux           # Linux
```

### 构建发布版

```bash
# Android APK
flutter build apk --release

# Android AAB (Google Play)
flutter build appbundle --release

# Web
flutter build web --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release
```

构建产物位于 `build/` 目录下。

---

## 🔐 登录说明

登录账号密码为 **飞牛影视的账号密码**，非本应用的独立账号。

- 服务器地址格式：`http://<你的NAS地址>:<端口>`
- 默认端口通常为 `5666`
- 勾选"记住密码"实现自动登录

---

## 🎬 弹幕使用

1. 确保弹幕服务器已部署（默认地址 `http://<NAS>:9321`）
2. 在 **设置 → 弹幕服务器** 中配置 API 地址
3. 播放时自动匹配弹幕，也可手动搜索
4. 在 **设置 → 弹幕设置** 中调整弹幕参数

---

## 🏗 CI/CD 自动构建

本项目使用 GitHub Actions 实现自动构建。当推送 `v*` 标签时，自动构建以下平台产物：

| 平台 | 产物格式 |
|------|----------|
| Android | `.apk` + `.aab` |
| Web | `.tar.gz` |
| Linux | `.tar.gz` |
| macOS | `.tar.gz` |
| Windows | `.zip` |

### 发布新版本

```bash
# 打标签并推送，触发自动构建
git tag v1.0.0
git push origin v1.0.0
```

构建完成后，GitHub Releases 页面会自动创建发布页，附带所有平台的构建产物。

### 手动触发

在 GitHub 仓库页面 → Actions → Build Release → Run workflow，输入版本号即可。

---

## 📋 API 接口

本项目对接飞牛影视以下 API：

| 接口 | 方法 | 说明 |
|------|------|------|
| `/v/api/v1/login` | POST | 用户登录 |
| `/v/api/v1/user/info` | GET | 获取用户信息 |
| `/v/api/v1/mediadb/list` | GET | 媒体库列表 |
| `/v/api/v1/item/list` | POST | 媒体条目列表 |
| `/v/api/v1/episode/list/{id}` | GET | 剧集列表 |
| `/v/api/v1/play/info` | POST | 播放信息 |
| `/v/api/v1/stream` | POST | 流媒体信息 |
| `/v/api/v1/media/range/{guid}` | GET | 视频流地址 |
| `/v/api/v1/play/record` | POST | 播放进度记录 |
| `/v/api/v1/item/watched` | POST | 标记已看 |
| `/v/api/v1/sys/img/{path}` | GET | 图片代理 |

所有请求需携带 `Authx` 签名头（MD5 签名算法见 `services/auth_utils.dart`）。

---

## 🙏 致谢

- [**fntv-electron**](https://github.com/QiaoKes/fntv-electron) — API 接口参考
- [**Danmu API**](https://github.com/huangxd-/danmu_api) — 弹幕数据服务
- **Flutter** — 跨平台 UI 框架

---

## ⚠️ 声明

本项目为**第三方客户端**，与飞牛影视官方无关。使用前请确保遵守相关服务条款。

---

## 📄 License

[GNU General Public License v3.0](LICENSE)
