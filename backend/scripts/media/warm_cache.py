#!/usr/bin/env python3
"""Warm Render/Cloudflare edge cache after a media deploy (read-only GETs).

Fetches master, every variant + subtitle playlist (and its vtt), and the first
N segments of every rendition, twice: pass 1 = before (cold?), pass 2 = after.
Prints TTFB + cf-cache-status / age per URL.

  python3 warm_cache.py [--base URL] [--eps mama-in-law-wahala/ep1,...] [--segments 2] [--passes 2]
Note: Render static sites send `cache-control: s-maxage=300`, so the edge keeps
objects ~5 min; re-run (or schedule) if you need it warm longer.
"""
import argparse, re, time, urllib.request
from urllib.parse import urljoin

def get(url):
    t0 = time.perf_counter()
    r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "naija-warm/1"}), timeout=30)
    first = r.read(1); ttfb = time.perf_counter() - t0
    body = first + r.read()
    h = r.headers
    return body, ttfb, r.status, h.get("cf-cache-status", "-"), h.get("age", "-"), time.perf_counter() - t0

def urls_for(master_url, nseg):
    out = [master_url]
    master = get(master_url)[0].decode()
    pls = [urljoin(master_url, u) for u in re.findall(r'URI="([^"]+)"', master)]
    pls += [urljoin(master_url, l) for l in master.splitlines() if l and not l.startswith("#")]
    for p in pls:
        out.append(p)
        lines = [l for l in get(p)[0].decode().splitlines() if l and not l.startswith("#")]
        out += [urljoin(p, l) for l in (lines if p.endswith("/subs/" + p.rsplit("/", 1)[-1]) and "/subs/" in p else lines[:nseg])]
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="https://naijareels-media.onrender.com")
    ap.add_argument("--eps", default="mama-in-law-wahala/ep1,mama-in-law-wahala/ep2")
    ap.add_argument("--segments", type=int, default=2)
    ap.add_argument("--passes", type=int, default=2)
    a = ap.parse_args()
    urls = []
    for ep in a.eps.split(","):
        urls += urls_for(f"{a.base.rstrip('/')}/{ep.strip()}/master.m3u8", a.segments)
    res = {u: [] for u in urls}
    for p in range(a.passes):
        for u in urls:
            try: _, ttfb, st, cf, age, tot = get(u); res[u].append((ttfb, st, cf, age))
            except Exception as e: res[u].append((float("nan"), str(e)[:20], "-", "-"))
    hdr = " | ".join(f"pass{i+1} ttfb/cf/age" for i in range(a.passes))
    print(f"{'url':60} | {hdr}")
    for u, r in res.items():
        print(f"{u.replace(a.base,''):60} | " + " | ".join(f"{t*1000:5.0f}ms {st} {cf:5} {age}" for t, st, cf, age in r))
    for i in range(a.passes):
        v = sorted(r[i][0] for r in res.values()); hits = sum(r[i][2] == "HIT" for r in res.values())
        print(f"pass{i+1}: n={len(v)} median={v[len(v)//2]*1000:.0f}ms max={v[-1]*1000:.0f}ms HIT={hits}/{len(v)}")

if __name__ == "__main__":
    main()
