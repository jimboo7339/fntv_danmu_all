#!/usr/bin/env python3
"""深度探测：play/info、stream、字幕 API"""
import hashlib, json, os, random, time, requests
from urllib.parse import urljoin, urlparse

API_KEY = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
API_SECRET = "16CCEB3D-AB42-077D-36A1-F355324E4237"
BASE = os.environ.get("FNOS_HOST", "http://192.168.100.10:8005")
USER = os.environ.get("FNOS_USER", "home")
PASS = os.environ.get("FNOS_PASS", "")

def md5hex(s): return hashlib.md5(s.encode()).hexdigest()

def gen_authx(path, body_str=None):
    nonce = str(100000 + random.randint(0, 899999))
    ts = str(int(time.time() * 1000))
    data_md5 = md5hex(body_str if body_str is not None else "")
    sign = md5hex(f"{API_KEY}_{path}_{nonce}_{ts}_{data_md5}_{API_SECRET}")
    return f"nonce={nonce}&timestamp={ts}&sign={sign}"

def call(method, path, token="", body=None):
    url = urljoin(BASE + "/", path.lstrip("/"))
    ap = urlparse(url).path
    body_str = json.dumps(body, separators=(",", ":"), ensure_ascii=False) if body is not None else None
    headers = {
        "Authx": gen_authx(ap, body_str),
        "Cookie": "mode=relay",
        "Accept": "*/*",
    }
    if body_str is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = token
    r = requests.request(method, url, headers=headers, data=body_str, timeout=25)
    ct = r.headers.get("Content-Type", "")
    if "json" in ct:
        return r.status_code, r.json()
    t = r.text
    return r.status_code, t if len(t) < 2000 else f"<{len(t)} chars ct={ct}>"

# login
nonce = str(random.randint(100000, 999999))
body = {"app_name": "trimemedia-web", "username": USER, "password": PASS, "nonce": nonce}
bs = json.dumps(body, separators=(",", ":"))
r = requests.post(BASE + "/v/api/v1/login",
    headers={"Authx": gen_authx("/v/api/v1/login", bs), "Content-Type": "application/json", "Cookie": "mode=relay"},
    data=bs)
token = r.json()["data"]["token"]
print("LOGIN OK\n")

results = []

def log(method, path, code, data):
    preview = json.dumps(data, ensure_ascii=False)[:500] if isinstance(data, (dict, list)) else str(data)[:500]
    print(f"{code:4} {method:4} {path}")
    if isinstance(data, str) and "-->" in data:
        print(f"     >>> SUBTITLE TEXT: {data[:200]}...")
    results.append({"method": method, "path": path, "status": code, "response": preview})

# 从继续观看取 item
_, pl = call("GET", "/v/api/v1/play/list", token)
item = pl["data"][0]["guid"] if pl.get("data") else None
print(f"item_guid={item}\n")

if item:
    c, detail = call("GET", f"/v/api/v1/item/{item}", token)
    log("GET", f"/v/api/v1/item/{item}", c, detail)

    c, pinfo = call("POST", "/v/api/v1/play/info", token, {"item_guid": item})
    log("POST", "/v/api/v1/play/info", c, pinfo)
    pd = pinfo.get("data") or {}
    media = pd.get("media_guid")
    sub = pd.get("subtitle_guid")
    video = pd.get("video_guid")
    audio = pd.get("audio_guid")
    print(f"media={media}\nsubtitle={sub}\nvideo={video}\naudio={audio}\n")

    if media:
        ip = md5hex(USER)
        c, stream = call("POST", "/v/api/v1/stream", token, {
            "media_guid": media, "ip": ip, "level": 1,
            "header": {"User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"]},
            "nonce": str(random.randint(100000, 999999)),
        })
        log("POST", "/v/api/v1/stream", c, stream)

        c, slist = call("GET", f"/v/api/v1/stream/list/{media}", token)
        log("GET", f"/v/api/v1/stream/list/{media}", c, slist)

        idx = 0
        subs = ((stream.get("data") or {}).get("subtitle_streams") or []) if isinstance(stream, dict) else []
        if subs:
            idx = subs[0].get("index", 0)
            print(f"subtitle_stream[0]: {subs[0]}\n")

        paths = [
            f"/v/api/v1/media/range/{media}?stream_index={idx}",
            f"/v/api/v1/media/range/{media}?stream_index={idx}&format=srt",
            f"/v/api/v1/media/range/{media}?stream=subtitle&stream_index={idx}",
            f"/v/api/v1/media/range/{media}?subtitle_index={idx}",
            f"/v/api/v1/media/range/{media}?type=3&index={idx}",
        ]
        if sub:
            paths = [f"/v/api/v1/media/range/{sub}"] + paths
        if video:
            paths.append(f"/v/api/v1/media/range/{video}?stream_index={idx}")
        paths += [
            f"/v/api/v1/media/subtitle/{media}",
            f"/v/api/v1/media/subtitle/{media}?stream_index={idx}",
            f"/v/api/v1/subtitle/{media}",
            f"/v/api/v1/subtitle/{media}?stream_index={idx}",
        ]
        for p in paths:
            c, data = call("GET", p, token)
            log("GET", p, c, data)

        c, person = call("POST", f"/v/api/v1/person/list/{item}", token, {"page": 1, "page_size": 10})
        log("POST", f"/v/api/v1/person/list/{item}", c, person)

# 修复 POST 签名后重测 item/list
ancestor = "07c93b9a26354903bdef0ae7620b990e"
c, items = call("POST", "/v/api/v1/item/list", token, {
    "ancestor_guid": ancestor, "page": 1, "page_size": 5,
    "exclude_grouped_video": 1, "sort_type": "updated_at", "sort_column": "desc",
})
log("POST", "/v/api/v1/item/list", c, items)

c, userdata = call("POST", "/v/api/v1/user/getData", token, {"keys": ["danmu"]})
log("POST", "/v/api/v1/user/getData", c, userdata)

# 更多 v1 路径
more = [
    ("GET", "/v/api/v1/season/list/92db96e90dc14402a114891f470eb8f2"),
    ("GET", "/v/api/v1/episode/list/92db96e90dc14402a114891f470eb8f2"),
    ("POST", "/v/api/v1/item/watched", {"item_guid": item, "watched": 1}),
    ("GET", "/v/api/v1/login"),
    ("POST", "/v/api/v1/logout"),
]
for m, p, *rest in [(x[0], x[1], x[2] if len(x)>2 else None) for x in [
    ("GET", "/v/api/v1/season/list/92db96e90dc14402a114891f470eb8f2"),
    ("GET", "/v/api/v1/episode/list/92db96e90dc14402a114891f470eb8f2"),
    ("POST", "/v/api/v1/item/watched", {"item_guid": item, "watched": 1}),
]]:
    b = rest[0] if rest else None
    c, d = call(m, p, token, b)
    log(m, p, c, d)

with open("tools/api_probe_deep.json", "w", encoding="utf-8") as f:
    json.dump({"server": BASE, "results": results}, f, ensure_ascii=False, indent=2)
print(f"\nSaved {len(results)} -> tools/api_probe_deep.json")
