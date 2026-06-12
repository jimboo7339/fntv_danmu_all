#!/usr/bin/env python3
"""字幕 API 专项探测"""
import hashlib, json, os, random, time, requests
from urllib.parse import urljoin, urlparse

API_KEY = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
API_SECRET = "16CCEB3D-AB42-077D-36A1-F355324E4237"
BASE = os.environ.get("FNOS_HOST", "http://192.168.100.10:8005")
USER = os.environ.get("FNOS_USER", "home")
PASS = os.environ.get("FNOS_PASS", "")

MEDIA = "6a3603174dc94bdf92fadfd34cbcbd2d"
SUB_GUID = "2ae941949d6b49f49e8e1b47f2a61493"
VIDEO = "53748c7fa6ba40218ecc63efd0803386"
ITEM = "156f65ae151c4aeca09fda58819e60e7"

def md5hex(s): return hashlib.md5(s.encode()).hexdigest()
def gen_authx(path, body_str=None):
    nonce = str(100000 + random.randint(0, 899999))
    ts = str(int(time.time() * 1000))
    data_md5 = md5hex(body_str if body_str is not None else "")
    sign = md5hex(f"{API_KEY}_{path}_{nonce}_{ts}_{data_md5}_{API_SECRET}")
    return f"nonce={nonce}&timestamp={ts}&sign={sign}"

def get(path, token, extra_headers=None):
    url = urljoin(BASE + "/", path.lstrip("/"))
    ap = urlparse(url).path
    h = {"Authx": gen_authx(ap), "Cookie": "mode=relay", "Accept": "*/*", "Authorization": token}
    if extra_headers:
        h.update(extra_headers)
    r = requests.get(url, headers=h, timeout=20)
    ct = r.headers.get("Content-Type", "")
    text = r.text
    if len(text) > 500:
        text = f"<{r.status_code} len={len(r.text)} ct={ct} head={r.text[:80]!r}>"
    return r.status_code, text

def post(path, token, body):
    url = urljoin(BASE + "/", path.lstrip("/"))
    ap = urlparse(url).path
    bs = json.dumps(body, separators=(",", ":"))
    h = {"Authx": gen_authx(ap, bs), "Cookie": "mode=relay", "Content-Type": "application/json", "Authorization": token}
    r = requests.post(url, headers=h, data=bs, timeout=20)
    if "json" in r.headers.get("Content-Type", ""):
        return r.status_code, r.json()
    return r.status_code, r.text[:300]

# login
nonce = str(random.randint(100000, 999999))
body = {"app_name": "trimemedia-web", "username": USER, "password": PASS, "nonce": nonce}
bs = json.dumps(body, separators=(",", ":"))
r = requests.post(BASE + "/v/api/v1/login",
    headers={"Authx": gen_authx("/v/api/v1/login", bs), "Content-Type": "application/json", "Cookie": "mode=relay"},
    data=bs)
token = r.json()["data"]["token"]

print("=== 字幕 index 探测 (0-5) ===")
for i in range(6):
    c, t = get(f"/v/api/v1/media/range/{MEDIA}?stream_index={i}", token)
    print(f"  stream_index={i} -> {c} {t[:100]}")

print("\n=== 带 Range 头 ===")
for p in [
    f"/v/api/v1/media/range/{MEDIA}?stream_index=3",
    f"/v/api/v1/media/range/{SUB_GUID}",
]:
    c, t = get(p, token, {"Range": "bytes=0-"})
    print(f"  Range {p[:60]} -> {c} {t[:100]}")

print("\n=== POST stream 带字幕参数 ===")
ip = md5hex(USER)
for extra in [
    {"subtitle_index": 3},
    {"subtitle_stream_index": 3},
    {"extract_subtitle": True, "stream_index": 3},
    {"subtitle": True},
]:
    b = {"media_guid": MEDIA, "ip": ip, "level": 1,
         "header": {"User-Agent": ["Mozilla/5.0"]}, "nonce": "123456", **extra}
    c, t = post("/v/api/v1/stream", token, b)
    print(f"  stream+{extra} -> {c} {str(t)[:150]}")

print("\n=== 其他路径 ===")
extras = [
    f"/v/api/v1/media/range/{MEDIA}?stream_index=3&output=srt",
    f"/v/api/v1/media/range/{MEDIA}?stream_index=3&transcode=0",
    f"/v/api/v1/media/range/{MEDIA}?stream_index=3&copyts=1",
    f"/v/api/v1/media/range/{MEDIA}?stream_type=subtitle&stream_index=3",
    f"/v/api/v1/media/range/{MEDIA}?codec_type=subtitle&index=3",
    f"/v/api/v1/media/subtitle/{MEDIA}/3",
    f"/v/api/v1/media/subtitle/{MEDIA}/3/srt",
    f"/v/api/v1/subtitle/{MEDIA}/3",
    f"/v/api/v1/subtitle/{MEDIA}/3/stream",
    f"/v/api/v1/subtitle/extract/{MEDIA}?index=3",
    f"/v/api/v1/media/range/{MEDIA}?stream_index=0",
    f"/v/api/v1/media/range/{MEDIA}?stream_index=1",
    f"/v/api/v1/media/range/{MEDIA}?stream_index=2",
]
for p in extras:
    c, t = get(p, token)
    if c not in (404, 501):
        print(f"  {c} {p[:70]} -> {t[:100]}")

print("\n=== play/info subtitle_guid 字段 ===")
c, pi = post("/v/api/v1/play/info", token, {"item_guid": ITEM})
print(json.dumps(pi, ensure_ascii=False, indent=2)[:1500])
