# 飞牛影视 (FnOS Media) API 文档

> 基于 FnOS 飞牛影视 v0.9.7 (mediasrv v0.8.35) 实际网络抓包分析  
> Base URL: `http://{NAS_IP}:8056`  
> 更新时间: 2026-06-11

---

## 目录

1. [认证机制](#1-认证机制)
2. [系统接口](#2-系统接口)
3. [用户接口](#3-用户接口)
4. [媒体库接口](#4-媒体库接口)
5. [条目详情接口](#5-条目详情接口)
6. [季/集接口](#6-季集接口)
7. [播放接口](#7-播放接口)
8. [流媒体接口](#8-流媒体接口)
9. [标签接口](#9-标签接口)
10. [人员接口](#10-人员接口)
11. [图片接口](#11-图片接口)
12. [用户数据存储接口](#12-用户数据存储接口)
13. [继续观看接口](#13-继续观看接口)

---

## 1. 认证机制

### 1.1 登录获取 Token

**POST** `/v/api/v2/user/loginByPassword`

请求体:
```json
{
  "username": "home",
  "password": "sha256hex(password)",
  "app_name": "trimemedia-web"
}
```

响应:
```json
{
  "msg": "",
  "code": 0,
  "data": {
    "token": "8563b1d0b0c84c8d953b234964c51df3"
  }
}
```

### 1.2 Authx 签名认证

所有 API 请求需要在 Header 中携带 `Authx` 字段，格式:

```
Authx: nonce={随机数}&timestamp={毫秒时间戳}&sign={MD5签名}
```

- **nonce**: 6位随机数字字符串
- **timestamp**: 当前毫秒级时间戳
- **sign**: `MD5(nonce + timestamp + token)` 的小写十六进制

> 注: 部分接口（如 `server/info`、`server/oauthStatus`）在登录前也需要 authx 签名，此时 token 为空字符串。

---

## 2. 系统接口

### 2.1 系统配置

**GET** `/v/api/v1/sys/config`

响应:
```json
{
  "code": 0,
  "data": {
    "default_img": {
      "bg_all": "/sys_type_all.png",
      "bg_movie": "/sys_type_movie.png",
      "bg_others": "/sys_type_others.png",
      "bg_tv": "/sys_type_tv.png"
    },
    "nas_oauth": {
      "app_id": "U1G8OGDF3Y",
      "url": "http://192.168.100.10:8056"
    },
    "initialized": true,
    "server_name": "飞牛影视",
    "server_guid": "914fade841244397a264ba6d64046e67",
    "supported_languages": ["zh-CN", "en"],
    "default_language": "zh-CN"
  }
}
```

### 2.2 系统版本

**GET** `/v/api/v1/sys/version`

响应:
```json
{
  "code": 0,
  "data": {
    "version": "0.9.7",
    "mediasrvVersion": "0.8.35"
  }
}
```

### 2.3 服务器信息

**GET** `/v/api/v1/server/info`

响应:
```json
{
  "code": 0,
  "data": {
    "guid": "914fade841244397a264ba6d64046e67",
    "name": "飞牛影视",
    "lan": "zh-CN",
    "file_monitor": 1,
    "gpu_acc": 1,
    "gpu_prefer": 1,
    "cpu_allow_decoding": 1,
    "meta_dir": "/vol1/@appmeta/trim.media",
    "mediasrv_cache_dir": "/vol1/mediasrv.transcode",
    "direct_link_enable": 1,
    "direct_link_allowed_level": 1,
    "supported_languages": ["zh-CN", "en"],
    "default_language": "zh-CN"
  }
}
```

### 2.4 OAuth状态

**GET** `/v/api/v1/server/oauthStatus`

响应:
```json
{
  "code": 0,
  "data": { "canUse": true }
}
```

### 2.5 授权目录

**GET** `/v/api/v1/server/getAppAuthorizedDir`

获取 App 授权的媒体目录列表。

---

## 3. 用户接口

### 3.1 登录

**POST** `/v/api/v2/user/loginByPassword`

见 [认证机制](#1-认证机制) 章节。

### 3.2 获取用户信息

**GET** `/v/api/v1/user/info`

需要认证。返回当前登录用户的详细信息。

---

## 4. 媒体库接口

### 4.1 媒体库列表

**GET** `/v/api/v1/mediadb/list`

获取所有媒体库（如"电影"、"电视节目"等顶级分类）。

### 4.2 媒体库统计

**GET** `/v/api/v1/mediadb/sum`

获取各媒体库的统计数据（数量等）。

---

## 5. 条目详情接口

### 5.1 获取条目详情

**GET** `/v/api/v1/item/{guid}`

**路径参数:**
| 参数 | 说明 |
|------|------|
| guid | 条目的唯一ID |

**响应字段:**
```json
{
  "code": 0,
  "data": {
    "guid": "07c93b9a26354903bdef0ae7620b990e",
    "title": "电视节目",
    "type": "MediaDB",
    "vote_average": "0",
    "is_favorite": 0,
    "is_watched": 0,
    "watched_ts": 0,
    "season_number": 0,
    "number_of_episodes": 0,
    "local_number_of_episodes": 0,
    "local_number_of_seasons": 0,
    "can_play": 1,
    "play_error": "",
    "parent_guid": "",
    "ancestor_name": "",
    "ancestor_category": "",
    "duration": 0,
    "logic_type": 0,
    "media_stream": {
      "resolutions": ["4k"],
      "audio_type": null,
      "color_range_type": null
    }
  }
}
```

### 5.2 条目列表（核心查询接口）

**POST** `/v/api/v1/item/list`

**请求体:**
```json
{
  "ancestor_guid": "07c93b9a26354903bdef0ae7620b990e",
  "tags": {
    "type": ["Movie", "TV", "Directory", "Video"],
    "genres": [2, 7],
    "resolutions": ["4k"],
    "color_range": ["HDR10"],
    "audio_type": ["Stereo"],
    "locate": ["CN"],
    "decades": ["2020s"],
    "recognition_status": [1]
  },
  "exclude_grouped_video": 1,
  "sort_type": "DESC",
  "sort_column": "release_date",
  "page": 1,
  "page_size": 22
}
```

**响应:**
```json
{
  "code": 0,
  "data": {
    "mdb_name": "",
    "mdb_category": "",
    "top_dir": "",
    "dir": "",
    "total": 44,
    "list": [
      {
        "guid": "0930b20a63d249ffb6e2ee0ae13c1f9c",
        "lan": "zh-CN",
        "imdb_id": "tt36982480",
        "trim_id": "tt287641",
        "tv_title": "",
        "title": "耀眼",
        "type": "TV",
        "poster": "/92/13/xxx.webp",
        "poster_width": 2000,
        "poster_height": 3000,
        "is_favorite": 0,
        "watched": 0,
        "watched_ts": 41,
        "vote_average": "6.2",
        "media_stream": {
          "resolutions": ["4k"],
          "audio_type": null,
          "color_range_type": ["SDR"]
        },
        "release_date": "2024-01-15",
        "season_number": 0,
        "number_of_episodes": 0,
        "local_number_of_episodes": 16,
        "local_number_of_seasons": 1,
        "ancestor_guid": "07c93b9a26354903bdef0ae7620b990e",
        "ancestor_name": "电视节目",
        "ancestor_category": "TV",
        "single_child_guid": "",
        "file_name": ""
      }
    ]
  }
}
```

---

## 6. 季/集接口

### 6.1 季列表

**GET** `/v/api/v1/season/list/{parent_guid}`

**路径参数:**
| 参数 | 说明 |
|------|------|
| parent_guid | 剧集(TV)的GUID |

**响应:**
```json
{
  "code": 0,
  "data": [
    {
      "guid": "92db96e90dc14402a114891f470eb8f2",
      "title": "第 1 季",
      "type": "Season",
      "parent_guid": "8b498d0f29b14feaa14e451ad9b865e3",
      "poster": "/48/01/xxx.webp",
      "release_date": "2026-06-02",
      "season_number": 1,
      "episode_number": 24,
      "local_number_of_episodes": 14,
      "ancestor_guid": "07c93b9a26354903bdef0ae7620b990e",
      "ancestor_name": "电视节目",
      "ancestor_category": "TV",
      "imdb_id": "tt37140755",
      "trim_id": "tt289271",
      "vote_average": "0",
      "media_stream": {"resolutions": ["4k"], "audio_type": null, "color_range_type": null}
    }
  ]
}
```

### 6.2 集列表

**GET** `/v/api/v1/episode/list/{season_guid}`

**路径参数:**
| 参数 | 说明 |
|------|------|
| season_guid | 季(Season)的GUID |

**响应:**
```json
{
  "code": 0,
  "data": [
    {
      "guid": "156f65ae151c4aeca09fda58819e60e7",
      "lan": "zh-CN",
      "imdb_id": "",
      "trim_id": "tt289271",
      "tv_title": "翘楚",
      "parent_guid": "92db96e90dc14402a114891f470eb8f2",
      "parent_title": "第 1 季",
      "title": "楚朝遭灭门傅九舍命",
      "type": "Episode",
      "poster": "/35/15/xxx.webp",
      "poster_width": 1920,
      "poster_height": 1080,
      "is_favorite": 0,
      "watched": 0,
      "watched_ts": 1038,
      "vote_average": "0",
      "media_stream": {"resolutions": ["4k"], "audio_type": null, "color_range_type": null},
      "season_number": 1,
      "episode_number": 1
    }
  ]
}
```

---

## 7. 播放接口

### 7.1 获取播放信息

**POST** `/v/api/v1/play/info`

**请求体:**
```json
{
  "item_guid": "8b498d0f29b14feaa14e451ad9b865e3"
}
```

**响应:**
```json
{
  "code": 0,
  "data": {
    "guid": "156f65ae151c4aeca09fda58819e60e7",
    "parent_guid": "92db96e90dc14402a114891f470eb8f2",
    "grand_guid": "",
    "media_guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
    "video_guid": "53748c7fa6ba40218ecc63efd0803386",
    "audio_guid": "b8071eda967f4826b016a4caa6d232c6",
    "subtitle_guid": "2ae941949d6b49f49e8e1b47f2a61493",
    "ts": 1038,
    "type": "Episode",
    "play_config": {"skip_opening": null, "skip_ending": null},
    "item": {
      "guid": "156f65ae151c4aeca09fda58819e60e7",
      "trim_id": "tt289271",
      "tv_title": "翘楚",
      "parent_title": "第 1 季",
      "title": "楚朝遭灭门傅九舍命",
      "posters": "/35/15/xxx.webp",
      "poster_width": 1920,
      "poster_height": 1080,
      "vote_average": "0",
      "release_date": "2026-06-02",
      "overview": "楚朝是大将军楚岺之女...",
      "is_favorite": 0,
      "is_watched": 0,
      "watched_ts": 1038,
      "still_path": "/3a/11/poster-xxx.webp",
      "air_date": "2026-06-02",
      "season_number": 1,
      "episode_number": 1,
      "number_of_seasons": 1,
      "number_of_episodes": 0,
      "local_number_of_episodes": 0,
      "ancestor_guid": "07c93b9a26354903bdef0ae7620b990e",
      "ancestor_name": "电视节目",
      "ancestor_category": "TV",
      "can_play": 1,
      "play_error": "",
      "duration": 0,
      "logic_type": 0,
      "media_stream": {"resolutions": null, "audio_type": null, "color_range_type": null}
    }
  }
}
```

### 7.2 上报播放进度

**POST** `/v/api/v1/play/record`

**请求体:**
```json
{
  "item_guid": "156f65ae151c4aeca09fda58819e60e7",
  "media_guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
  "video_guid": "53748c7fa6ba40218ecc63efd0803386",
  "audio_guid": "b8071eda967f4826b016a4caa6d232c6",
  "subtitle_guid": "2ae941949d6b49f49e8e1b47f2a61493",
  "resolution": "原画",
  "bitrate": 0,
  "ts": 1038,
  "duration": 2857
}
```

**响应:**
```json
{
  "code": 0,
  "data": true
}
```

---

## 8. 流媒体接口

### 8.1 获取播放流信息

**POST** `/v/api/v1/stream`

**请求体:**
```json
{
  "media_guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
  "ip": "md5hex(account_name)",
  "header": {"User-Agent": ["Mozilla/5.0 ..."]},
  "level": 1
}
```

**响应:**
```json
{
  "code": 0,
  "data": {
    "file_stream": {
      "guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
      "path": "/vol1/1000/video/xxx.mkv",
      "file_name": "xxx.mkv",
      "size": 2332695484,
      "type": 1,
      "can_play": 1,
      "play_error": ""
    },
    "video_stream": {
      "media_guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
      "codec_name": "h264",
      "width": 3840,
      "height": 1608
    },
    "audio_streams": [
      {"title": "", "language": "und", "codec_name": "aac", "channels": 2, "index": 0}
    ],
    "subtitle_streams": [
      {"title": "", "language": "und", "codec_name": "mov_text", "index": 0}
    ],
    "qualities": [
      {"bitrate": 6255343, "resolution": "4k",  "progressive": true, "is_m3u8": false},
      {"bitrate": 5000000, "resolution": "1080", "progressive": true, "is_m3u8": false},
      {"bitrate": 4000000, "resolution": "1080", "progressive": true, "is_m3u8": false},
      {"bitrate": 5000000, "resolution": "720",  "progressive": true, "is_m3u8": false},
      {"bitrate": 4000000, "resolution": "720",  "progressive": true, "is_m3u8": false},
      {"bitrate": 3000000, "resolution": "720",  "progressive": true, "is_m3u8": false}
    ],
    "cloud_storage_info": {
      "valid": true,
      "disabled": false,
      "cloud_storage_type": 9001,
      "cloud_nick_name": "strm文件",
      "is_vip": false
    },
    "header": {"User-Agent": ["Mozilla/5.0 ..."]},
    "direct_link_qualities": [
      {
        "bitrate": 0,
        "resolution": "原画",
        "progressive": false,
        "url": "https://video-play-p-zb.drive.quark.cn/..."
      }
    ]
  }
}
```

**关键说明:**
- `qualities`: 服务器转码画质列表（progressive=true 渐进式下载）
- `direct_link_qualities`: 云盘直链画质，URL 为外部网盘直接播放链接
- `cloud_storage_type`: 9001 = strm 文件（网盘串流）

### 8.2 获取媒体流列表

**GET** `/v/api/v1/stream/list/{media_guid}`

获取指定媒体文件的音视频字幕流列表（strm 文件可能返回空）。

---

## 9. 标签接口

### 9.1 标签列表

**GET** `/v/api/v1/tag/list`

**查询参数:**
| 参数 | 说明 |
|------|------|
| ancestor_guid | 媒体库GUID |
| is_favorite | 是否只看收藏 (0/1) |

**响应:**
```json
{
  "code": 0,
  "data": {
    "genres": [2, 7, 1, 4, 8, 13, 5, 9, 18, 10, 11, 17, 14, 30, 90001],
    "resolutions": ["4k"],
    "color_range": ["HDR10", "SDR"],
    "audio_type": ["Stereo"],
    "locate": ["CN", "US", "MD", "KR", "GB", "CL"],
    "decades": ["Recent", "2020s", "2010s", "Others"],
    "recognition_status": [1, 2, 3]
  }
}
```

### 9.2 类型标签详情

**GET** `/v/api/v1/tag/genres?lan=zh-CN`

### 9.3 地区标签

**GET** `/v/api/v1/tag/iso3166?lan=zh-CN`

### 9.4 语言标签

**GET** `/v/api/v1/tag/iso6391?lan=zh-CN`  
**GET** `/v/api/v1/tag/iso6392?lan=zh-CN`

---

## 10. 人员接口

### 10.1 人员列表

**POST** `/v/api/v1/person/list/{item_guid}`

**请求体:**
```json
{"page": 1, "page_size": 200}
```

**响应:**
```json
{
  "code": 0,
  "data": {
    "total": 9,
    "list": [
      {
        "person_guid": "4be56c9385514d54bb38a0fa004b8aba",
        "job": "Director",
        "order": 1,
        "trim_id": "tp2192226",
        "imdb_id": "nm5769572",
        "tmdb_id": 2192226,
        "name": "杨龙",
        "original_name": "杨龙",
        "biography": "杨龙，本科毕业于...",
        "known_for_department": "Directing",
        "profile_path": "/96/19/xxx.webp"
      }
    ]
  }
}
```

---

## 11. 图片接口

### 11.1 图片代理

**GET** `/v/api/v1/sys/img/{prefix}/{hash}/{full_hash}.webp`

所有图片通过此接口代理。图片路径来自其他 API 响应中的 `poster`、`still_path`、`profile_path` 等字段。

**完整URL:**
```
http://{NAS_IP}:8056/v/api/v1/sys/img{poster_path}
```

需要认证头 (Authx)。

---

## 12. 用户数据存储接口

### 12.1 获取用户数据

**POST** `/v/api/v1/user/getData`

**请求体:**
```json
{"key": "mdb:list:setting"}
```

**已知 key 值:**

| Key | 说明 |
|-----|------|
| `mdb:list:setting` | 媒体库列表视图设置 |
| `playlist:setting` | 播放列表视图设置 |
| `list:card:setting` | 卡片列表设置 |

---

## 13. 继续观看接口

### 13.1 继续观看列表

**GET** `/v/api/v1/play/list`

**响应:**
```json
{
  "code": 0,
  "data": [
    {
      "guid": "156f65ae151c4aeca09fda58819e60e7",
      "tv_title": "翘楚",
      "parent_guid": "92db96e90dc14402a114891f470eb8f2",
      "title": "楚朝遭灭门傅九舍命",
      "type": "Episode",
      "poster": "/35/15/xxx.webp",
      "poster_width": 1920,
      "poster_height": 1080,
      "is_favorite": 0,
      "watched": 0,
      "watched_ts": 0,
      "season_number": 1,
      "episode_number": 1,
      "ancestor_guid": "07c93b9a26354903bdef0ae7620b990e",
      "ancestor_name": "电视节目",
      "ancestor_category": "TV",
      "ts": 1038,
      "duration": 2857,
      "media_guid": "6a3603174dc94bdf92fadfd34cbcbd2d",
      "video_guid": "53748c7fa6ba40218ecc63efd0803386",
      "audio_guid": "b8071eda967f4826b016a4caa6d232c6",
      "subtitle_guid": "2ae941949d6b49f49e8e1b47f2a61493"
    }
  ]
}
```

---

## 附录: 完整播放流程

```
1. 登录
   POST /v/api/v2/user/loginByPassword → 获取 token

2. 获取媒体库
   GET  /v/api/v1/mediadb/list → 获取媒体库 GUID

3. 获取条目列表
   POST /v/api/v1/item/list (ancestor_guid=媒体库GUID) → Movie/TV 列表

4. 获取季列表 (TV)
   GET  /v/api/v1/season/list/{tv_guid} → Season 列表

5. 获取集列表 (TV)
   GET  /v/api/v1/episode/list/{season_guid} → Episode 列表

6. 获取播放信息
   POST /v/api/v1/play/info (item_guid=episode_guid) → media_guid, ts

7. 获取播放流
   POST /v/api/v1/stream (media_guid, ip=md5(account)) → 播放URL和流信息

8. 播放
   - 转码: qualities 中的 URL
   - 直链: direct_link_qualities 中的 url

9. 上报进度
   POST /v/api/v1/play/record (item_guid, media_guid, ts, duration)
```

---

## 附录: 数据类型

### type 字段值

| 值 | 说明 |
|----|------|
| `MediaDB` | 媒体库顶层 |
| `Movie` | 电影 |
| `TV` | 电视剧 |
| `Season` | 季 |
| `Episode` | 集 |
| `Video` | 独立视频文件 |
| `Directory` | 目录 |

### cloud_storage_type 字段值

| 值 | 说明 |
|----|------|
| 9001 | strm 文件（网盘串流） |

---

## 附录: 新发现接口

| 接口 | 说明 | 状态 |
|------|------|------|
| `POST /v/api/v1/user/getData` | 用户偏好设置 KV 存储 | 🆕 新发现 |
| `GET /v/api/v1/server/oauthStatus` | OAuth 状态 | 🆕 新发现 |
| `GET /v/api/v1/server/getAppAuthorizedDir` | 授权目录 | 🆕 新发现 |
| `GET /v/api/v1/tag/list` | 筛选标签列表 | 🆕 新发现 |
| `GET /v/api/v1/tag/genres` | 类型标签映射 | 🆕 新发现 |
| `GET /v/api/v1/tag/iso3166` | 国家/地区标签 | 🆕 新发现 |
| `GET /v/api/v1/tag/iso6391` | 语言标签(639-1) | 🆕 新发现 |
| `GET /v/api/v1/tag/iso6392` | 语言标签(639-2) | 🆕 新发现 |
| `GET /v/api/v1/stream/list/{guid}` | 媒体流列表 | 🆕 新发现 |
| `POST /v/api/v1/person/list/{guid}` | 演员/导演信息 | 🆕 新发现 |
| `GET /v/api/v1/server/info` | 服务器详情 | ⚠️ 部分已有 |
| `POST /v/api/v1/stream` | 播放流获取 | ✅ 已有 |
| `POST /v/api/v1/play/record` | 进度上报 | ✅ 已有 |
| `GET /v/api/v1/play/list` | 继续观看 | ✅ 已有 |
| `POST /v/api/v1/play/info` | 播放信息 | ✅ 已有 |
| `POST /v/api/v1/item/list` | 条目列表 | ✅ 已有 |
| `GET /v/api/v1/episode/list` | 集列表 | ✅ 已有 |
| `GET /v/api/v1/season/list` | 季列表 | ✅ 已有 |
| `GET /v/api/v1/item/{guid}` | 条目详情 | ✅ 已有 |
| `GET /v/api/v1/sys/config` | 系统配置 | ✅ 已有 |
| `GET /v/api/v1/sys/version` | 版本信息 | ✅ 已有 |
| `GET /v/api/v1/sys/img/...` | 图片代理 | ✅ 已有 |
