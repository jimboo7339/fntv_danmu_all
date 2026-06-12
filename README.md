# 飞牛TV 弹幕版 🎬

> 基于飞牛影视 (FnOS) 的第三方播放器客户端，主打弹幕体验和播放器功能增强。

---

## ✨ 核心功能

### 🎯 弹幕系统
- **自动匹配** — 播放时自动从弹幕服务器搜索匹配番剧，按剧名缓存弹幕源
- **手动搜索** — 支持手动搜索弹幕源，精确匹配
- **滚动/顶部/底部** — 三种弹幕模式，完整解析 `m`/`p` 格式
- **密度控制** — 行尾智能间距，不重叠不拥挤
- **全面自定义** — 透明度、字号、显示区域、滚动速度、密度、描边、顶部边距均可调

### ▶️ 播放器
- **MPV 内核** — media_kit (libmpv) 驱动，支持硬件解码
- **手势控制** — 左侧上下滑=亮度，右侧上下滑=音量，横向滑动=进度，长按=倍速
- **倍速播放** — 0.5x ~ 3.0x，长按倍速可在设置中配置（1.5/2/2.5/3x）
- **音轨/字幕切换** — 多音轨时可选语言/编码，多字幕时可选字幕+关闭
- **字幕样式** — 字号、颜色、底部距离可调，实时预览
- **自动连播** — 剧集播完自动播放下一集
- **续播** — 记忆播放进度，下次自动跳转到上次位置
- **比例切换** — 自动检测视频比例，支持手动切换

### 📺 媒体浏览
- **媒体库** — 展示所有媒体库，点击进入浏览
- **详情页** — 海报模糊背景 + palette 取色 + Logo 展示 + 演员列表
- **选集视图** — 三种模式：详细列表 / 封面九宫格 / 数字按钮
- **继续观看** — 首页展示未看完的剧集，进度条可视化

### ⚙️ 设置
- **播放器设置** — 内核选择(MPV/Exo)、解码模式、手势配置
- **弹幕设置** — 弹幕服务器、样式、搜索管理
- **账号管理** — 多账号切换
- **二级菜单** — 精简为 5 个入口卡片

---

## 📸 截图

| 首页 | 详情页 | 播放器 |
|------|--------|--------|
| 继续观看 + 媒体库入口 <img width="1272" height="2772" alt="9f99c9ab0d5ad2de40625e885863158c" src="https://github.com/user-attachments/assets/c58b4ed4-196f-43bb-8f57-d872625c1314" />| 海报模糊 + Logo + 信息标签 <img width="1272" height="2772" alt="a14c1ebd1aeb01bea89b53eb04139739" src="https://github.com/user-attachments/assets/3f843b8a-6993-4c41-883b-aee51364f35c" /><img width="1272" height="2772" alt="09d7493f74c4256bdc60342b9c67eb01" src="https://github.com/user-attachments/assets/0dedde12-1bfb-4962-8fce-f6f3e6f591be" />| 弹幕 + 手势控制 <img width="2772" height="1272" alt="e2e75a24471e8d6038f1a40831ffed1a" src="https://github.com/user-attachments/assets/4e229e35-916b-42b0-a135-ffe7e8e02c9a" />|

---

## 🛠 技术栈

| 层级 | 技术 |
|------|------|
| 框架 | Flutter 3.x + Dart 3.x |
| 状态管理 | Provider |
| 网络请求 | Dio + Authx 签名 |
| 视频播放 | media_kit (MPV) + ExoPlayer |
| 弹幕渲染 | CustomPainter 自绘引擎 |
| 图片缓存 | cached_network_image + 认证头 |
| 调色板 | palette_generator |
| CI/CD | GitHub Actions |

---

## 📦 下载

前往 [Releases](https://github.com/jimboo7339/fntv_danmu_all/releases) 页面下载最新 APK。

> 💡 国内加速下载：在 Release 下载链接前加 `https://docker.beehub.top/` 前缀

---

## 🚀 快速开始

### 环境要求

- Flutter SDK >= 3.24
- Dart SDK >= 3.5
- Android Studio / Xcode（按目标平台）

### 本地运行

```bash
git clone git@github.com:jimboo7339/fntv_danmu_all.git
cd fntv_danmu_all
flutter pub get
flutter run
```

### 构建 APK

```bash
flutter build apk --release
```

---

## 🔐 登录

- **服务器地址** — `http://<你的NAS地址>:<端口>`（默认端口 5666）
- **账号密码** — 飞牛影视的账号密码，非本应用独立账号
- **记住密码** — 勾选后自动登录

---

## 🎬 弹幕使用

1. 确保弹幕服务器已部署（默认端口 9321）
2. 在 **设置 → 弹幕设置** 中配置弹幕服务器地址
3. 播放时自动搜索匹配弹幕
4. 长按播放器弹幕按钮可手动搜索/切换弹幕源

---

## 📋 项目结构

```
lib/
├── main.dart
├── models/                    # 数据模型
│   ├── play_info.dart         #   播放信息
│   ├── play_list_item.dart    #   播放列表项
│   ├── danmu_comment.dart     #   弹幕评论
│   └── watch_record.dart      #   观看记录
├── services/                  # 网络服务
│   ├── api_client.dart        #   API 客户端
│   └── video_wrapper.dart     #   视频包装器 (MPV/Exo)
├── providers/
│   └── app_state.dart         #   全局状态
├── screens/                   # 页面
│   ├── login_screen.dart      #   登录
│   ├── home_screen.dart       #   首页
│   ├── detail_screen.dart     #   详情页
│   ├── player_screen.dart     #   播放器
│   ├── library_screen.dart    #   媒体库
│   └── settings_screen.dart   #   设置
├── widgets/                   # 组件
│   ├── danmu_overlay.dart     #   弹幕覆盖层
│   ├── player_controls.dart   #   播放控制栏
│   ├── media_card.dart        #   媒体卡片
│   └── continue_watching_card.dart
└── utils/
    ├── theme.dart             #   主题
    └── format.dart            #   格式化
```

---

## 🏗 CI/CD

推送 `v*` 标签自动触发 GitHub Actions 构建：

```bash
git tag v0.1.0
git push origin v0.1.0
```

构建产物：Android APK（自动发布到 Releases）

---

## 🙏 致谢

- [fntv-electron](https://github.com/QiaoKes/fntv-electron) — API 接口参考
- [Danmu API](https://github.com/huangxd-/danmu_api) — 弹幕数据服务
- [media_kit](https://github.com/media-kit/media-kit) — 跨平台视频播放
- Flutter — 跨平台 UI 框架

---

## ⚠️ 声明

本项目为第三方客户端，与飞牛影视官方无关。使用前请确保遵守相关服务条款。

---

## 📄 License

[GNU General Public License v3.0](LICENSE)
