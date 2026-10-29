#!/usr/bin/env python3
"""Check every subs/<lang>.vtt has the same cue count and timings as en.vtt, and lines <= 42 chars x 2."""
import glob, os, re, sys
bad = 0
for d in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "../../media/*/ep*/subs"))):
    ref = re.findall(r"^(\S+ --> \S+)$", open(f"{d}/en.vtt").read(), re.M)
    for f in sorted(glob.glob(f"{d}/*.vtt")):
        txt = open(f, encoding="utf-8").read()
        t = re.findall(r"^(\S+ --> \S+)$", txt, re.M)
        blocks = [b.split("\n")[2:] for b in txt.strip().split("\n\n")[1:]]
        long = sum(1 for b in blocks if len(b) > 2 or any(len(l) > (18 if re.search(r'[\u3000-\u9fff\uff00-\uffef]', l) else 42) for l in b))
        ok = t == ref and txt.startswith("WEBVTT") and not long
        bad += not ok
        print(f"{'OK ' if ok else 'BAD'} {os.path.relpath(f, d + '/../../..')}: cues={len(t)}/{len(ref)} timings_equal={t == ref} overlong={long}")
# master.m3u8: 6 SUBTITLES renditions, every variant references the group, every playlist probes as webvtt
import subprocess
for m in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "../../media/*/ep*/master.m3u8"))):
    txt = open(m).read(); d = os.path.dirname(m)
    if "TYPE=SUBTITLES" not in txt:
        continue
    media = re.findall(r'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="[^"]+",LANGUAGE="([^"]+)",DEFAULT=NO,AUTOSELECT=YES[^\n]*URI="([^"]+)"', txt)
    variants = re.findall(r"#EXT-X-STREAM-INF:[^\n]*", txt)
    probed = []
    for lang, uri in media:
        r = subprocess.run(["ffprobe", "-v", "error", "-allowed_extensions", "ALL", "-show_entries", "stream=codec_name", "-of", "csv=p=0", os.path.join(d, os.path.dirname(uri), re.findall(r"^[^#\s].*$", open(os.path.join(d, uri)).read(), re.M)[0])], capture_output=True, text=True)
        probed.append(r.stdout.strip() == "webvtt")
    ok = len(media) == 7 and all(probed) and variants and all('SUBTITLES="subs"' in v for v in variants)
    bad += not ok
    print(f"{'OK ' if ok else 'BAD'} {os.path.relpath(m, d + '/../..')}: subtitle renditions={[l for l, _ in media]} webvtt_probe(playlist→vtt)={sum(probed)}/{len(media)} variants_with_group={sum('SUBTITLES=\"subs\"' in v for v in variants)}/{len(variants)}")
sys.exit(1 if bad else 0)
