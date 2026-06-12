#!/usr/bin/env python3
"""飞牛影视 API 探测 — 登录后批量请求并记录响应。"""
import hashlib
import json
import os
import random
import sys
import time
from urllib.parse import urljoin, urlparse

try:
    import requests
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests

API_KEY = "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh"
API_SECRET = "16CCEB3D-AB42-077D-36A1-F355324E4237"

BASE = os.environ.get("FNOS_HOST", "http://192.168.100.10:8005")
USER = os.environ.get("FNOS_USER", "home")
PASS = os.environ.get("FNOS_PASS", "")


def md5hex(s: str) -> str:
    return hashlib.md5(s.encode()).hexdigest()


def gen_authx(path: str, body: str | None = None) -> str:
    nonce = str(100000 + random.randint(0, 899999))
    ts = str(int(time.time() * 1000))
    data_md5 = md5hex(body if body is not None else "")
    sign_str = f"{API_KEY}_{path}_{nonce}_{ts}_{data_md5}_{API_SECRET}"
    return f"nonce={nonce}&timestamp={ts}&sign={md5hex(sign_str)}"


def api_call(method: str, path: str, token: str = "", body=None, params=None, timeout=20):
    url = urljoin(BASE + "/", path.lstrip("/"))
    auth_path = urlparse(url).path
    body_str = json.dumps(body, separators=(",", ":")) if body is not None else None
    headers = {
        "Authx": gen_authx(auth_path, body_str),
        "Cookie": "mode=relay",
        "Accept": "application/json, text/plain, application/x-subrip, text/vtt, */*",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = token
    try:
        r = requests.request(
            method, url, headers=headers,
            json=body if body is not None else None,
            params=params, timeout=timeout,
        )
        ct = r.headers.get("Content-Type", "")
        if "json" in ct:
            return r.status_code, r.json()
        text = r.text
        if len(text) > 3000:
            return r.status_code, f"<text {len(text)} chars, ct={ct}>"
        return r.status_code, text
    except Exception as e:
        return -1, str(e)


def sample(data, max_len=600):
    if isinstance(data, (dict, list)):
        s = json.dumps(data, ensure_ascii=False)
    else:
        s = str(data)
    return s[:max_len] + ("..." if len(s) > max_len else "")


def login() -> str:
    # v1/login (Flutter app)
    nonce = str(100000 + random.randint(0, 899999))
    body = {"app_name": "trimemedia-web", "username": USER, "password": PASS, "nonce": nonce}
    path = "/v/api/v1/login"
    body_str = json.dumps(body, separators=(",", ":"))
    r = requests.post(
        BASE + path,
        headers={"Authx": gen_authx(path, body_str), "Content-Type": "application/json", "Cookie": "mode=relay"},
        json=body, timeout=15,
    )
    if r.status_code == 200:
        j = r.json()
        if j.get("code") == 0 and j.get("data", {}).get("token"):
            print(f"[OK] v1/login  token={j['data']['token'][:20]}...")
            return j["data"]["token"]

    # v2/sha256
    for pw in [hashlib.sha256(PASS.encode()).hexdigest(), md5hex(PASS)]:
        body2 = {"username": USER, "password": pw, "app_name": "trimemedia-web"}
        path2 = "/v/api/v2/user/loginByPassword"
        body2_str = json.dumps(body2, separators=(",", ":"))
        r2 = requests.post(
            BASE + path2,
            headers={"Authx": gen_authx(path2, body2_str), "Content-Type": "application/json", "Cookie": "mode=relay"},
            json=body2, timeout=15,
        )
        if r2.status_code == 200:
            j2 = r2.json()
            if j2.get("code") == 0 and j2.get("data", {}).get("token"):
                print(f"[OK] v2/login  token={j2['data']['token'][:20]}...")
                return j2["data"]["token"]

    print(f"[FAIL] v1: {r.status_code} {r.text[:300]}")
    sys.exit(1)


def main():
    token = login()
    results = []
    sample_item = sample_media = sample_subtitle = None

    static = [
        ("GET", "/v/api/v1/sys/config"),
        ("GET", "/v/api/v1/sys/version"),
        ("GET", "/v/api/v1/server/info"),
        ("GET", "/v/api/v1/server/oauthStatus"),
        ("GET", "/v/api/v1/server/getAppAuthorizedDir"),
        ("GET", "/v/api/v1/user/info"),
        ("GET", "/v/api/v1/mediadb/list"),
        ("GET", "/v/api/v1/mediadb/sum"),
        ("GET", "/v/api/v1/play/list"),
        ("GET", "/v/api/v1/tag/list"),
        ("GET", "/v/api/v1/tag/genres", None, {"lan": "zh-CN"}),
        ("GET", "/v/api/v1/tag/iso3166", None, {"lan": "zh-CN"}),
        ("GET", "/v/api/v1/tag/iso6391", None, {"lan": "zh-CN"}),
        ("GET", "/v/api/v1/tag/iso6392", None, {"lan": "zh-CN"}),
        ("POST", "/v/api/v1/user/getData", {"keys": []}),
    ]

    for item in static:
        method, path = item[0], item[1]
        body = item[2] if len(item) > 2 else None
        params = item[3] if len(item) > 3 else None
        code, data = api_call(method, path, token, body, params)
        results.append({"method": method, "path": path, "status": code, "response": sample(data)})
        print(f"{code:4} {method:4} {path}")

    # item list
    _, mediadb = api_call("GET", "/v/api/v1/mediadb/list", token)
    ancestor = None
    if isinstance(mediadb, dict):
        dbs = mediadb.get("data") or []
        if dbs:
            ancestor = dbs[0].get("guid")

    if ancestor:
        code, items = api_call("POST", "/v/api/v1/item/list", token, {
            "ancestor_guid": ancestor, "page": 1, "page_size": 20,
            "exclude_grouped_video": 1, "sort_type": "updated_at", "sort_column": "desc",
        })
        results.append({"method": "POST", "path": "/v/api/v1/item/list", "status": code, "response": sample(items)})
        print(f"{code:4} POST /v/api/v1/item/list")
        if isinstance(items, dict):
            lst = (items.get("data") or {}).get("list") or []
            for it in lst:
                t, g = it.get("type"), it.get("guid")
                if t == "Episode" and g:
                    sample_item = g
                    break
                if t == "Movie" and g and not sample_item:
                    sample_item = g
                if t == "TV" and g:
                    tv_guid = g

            # 尝试 TV -> season -> episode
            if not sample_item and 'tv_guid' in dir():
                _, seasons = api_call("GET", f"/v/api/v1/season/list/{tv_guid}", token)
                if isinstance(seasons, dict):
                    sl = (seasons.get("data") or {}).get("list") or seasons.get("data") or []
                    if sl and isinstance(sl, list):
                        sg = sl[0].get("guid")
                        if sg:
                            _, eps = api_call("GET", f"/v/api/v1/episode/list/{sg}", token)
                            if isinstance(eps, dict):
                                el = (eps.get("data") or {}).get("list") or eps.get("data") or []
                                if el:
                                    sample_item = el[0].get("guid")

    if sample_item:
        for p in [f"/v/api/v1/item/{sample_item}"]:
            code, data = api_call("GET", p, token)
            results.append({"method": "GET", "path": p, "status": code, "response": sample(data)})
            print(f"{code:4} GET {p}")

        code, pinfo = api_call("POST", "/v/api/v1/play/info", token, {"item_guid": sample_item})
        results.append({"method": "POST", "path": "/v/api/v1/play/info", "status": code, "response": sample(pinfo)})
        print(f"{code:4} POST /v/api/v1/play/info")
        if isinstance(pinfo, dict):
            pd = pinfo.get("data") or {}
            sample_media = pd.get("media_guid")
            sample_subtitle = pd.get("subtitle_guid")
            print(f"     media_guid={sample_media} subtitle_guid={sample_subtitle}")

    if sample_media:
        ip_hash = md5hex(USER)
        code, stream = api_call("POST", "/v/api/v1/stream", token, {
            "media_guid": sample_media, "ip": ip_hash, "level": 1,
            "header": {"User-Agent": ["Mozilla/5.0"]},
            "nonce": str(random.randint(100000, 999999)),
        })
        results.append({"method": "POST", "path": "/v/api/v1/stream", "status": code, "response": sample(stream)})
        print(f"{code:4} POST /v/api/v1/stream")

        code, slist = api_call("GET", f"/v/api/v1/stream/list/{sample_media}", token)
        results.append({"method": "GET", "path": f"/v/api/v1/stream/list/{{media_guid}}", "status": code, "response": sample(slist)})
        print(f"{code:4} GET /v/api/v1/stream/list/{sample_media}")

        sub_idx = 0
        if isinstance(stream, dict):
            subs = ((stream.get("data") or {}).get("subtitle_streams")) or []
            if subs:
                sub_idx = subs[0].get("index", 0)

        subtitle_tests = [
            f"/v/api/v1/media/range/{sample_media}?stream_index={sub_idx}",
            f"/v/api/v1/media/range/{sample_media}?stream_index={sub_idx}&format=srt",
            f"/v/api/v1/media/range/{sample_media}?stream=subtitle&stream_index={sub_idx}",
            f"/v/api/v1/media/subtitle/{sample_media}",
            f"/v/api/v1/media/subtitle/{sample_media}?stream_index={sub_idx}",
            f"/v/api/v1/subtitle/{sample_media}",
            f"/v/api/v1/subtitle/{sample_media}?stream_index={sub_idx}",
        ]
        if sample_subtitle:
            subtitle_tests.insert(0, f"/v/api/v1/media/range/{sample_subtitle}")

        for p in subtitle_tests:
            code, data = api_call("GET", p, token)
            resp = sample(data)
            if isinstance(data, str) and "-->" in data:
                resp = f"[SUBTITLE TEXT {len(data)} chars] {data[:200]}..."
            results.append({"method": "GET", "path": p, "status": code, "response": resp})
            print(f"{code:4} GET {p[:90]}")

        if sample_item:
            code, person = api_call("POST", f"/v/api/v1/person/list/{sample_item}", token, {"page": 1, "page_size": 10})
            results.append({"method": "POST", "path": "/v/api/v1/person/list/{item_guid}", "status": code, "response": sample(person)})
            print(f"{code:4} POST /v/api/v1/person/list/...")

    # 额外路径探测
    extras = [
        ("GET", "/v/api/v1/search"),
        ("POST", "/v/api/v1/search"),
        ("GET", "/v/api/v1/item/search"),
        ("POST", "/v/api/v1/item/search", {"keyword": "test", "page": 1}),
        ("GET", "/v/api/v1/favorite/list"),
        ("POST", "/v/api/v1/item/watched", {"item_guid": sample_item or "", "watched": 0}),
        ("GET", "/v/api/v1/transcode/status"),
        ("POST", "/v/api/v1/media/subtitle/extract", {"media_guid": sample_media or "", "stream_index": 0}),
        ("GET", "/v/api/v1/subtitle/list"),
        ("GET", "/v/api/v2/user/info"),
        ("POST", "/v/api/v1/play/record", {"item_guid": sample_item or "", "media_guid": sample_media or "", "ts": 0, "duration": 100}),
    ]
    for item in extras:
        method, path = item[0], item[1]
        body = item[2] if len(item) > 2 else None
        code, data = api_call(method, path, token, body)
        if code not in (404, 405, -1):
            results.append({"method": method, "path": path, "status": code, "response": sample(data)})
            print(f"{code:4} {method:4} {path} [probe]")

    out_path = "tools/api_probe_results.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"server": BASE, "probed_at": time.strftime("%Y-%m-%d %H:%M:%S"), "count": len(results), "endpoints": results}, f, ensure_ascii=False, indent=2)
    print(f"\n=== Done: {len(results)} endpoints -> {out_path} ===")


if __name__ == "__main__":
    main()
