#!/usr/bin/env python3
"""NaijaReels multi-language subtitle pipeline (re-runnable).

Usage:
  python3 scripts/subs/pipeline.py --ep 1 [--slug mama-in-law-wahala] [--src-dir /workspace/naija-drama]
         [--provider manual|openai] [--transcode] [--video PATH] [--en PATH]

Steps:
  1. Source EN subs: <src>/epNN/epNN_en.vtt (preferred, speech-aligned) else <src>/epNN/subs_en.srt.
  2. (--transcode, or auto when epNN_final.mp4 exists and --transcode given) re-encode video to
     media/<slug>/epN/{360p,720p}/index.m3u8 with 4s segments (H.264/AAC).
  3. Translate cue texts per language via a provider; cue count and timings are kept identical.
     - manual: reads scripts/subs/translations/epNN/<lang>.json (array of strings, one per cue)
     - openai: needs OPENAI_API_KEY; results are cached into the same JSON files (review before deploy)
  4. Wrap lines (<=42 chars, max 2 lines), write media/<slug>/epN/subs/<lang>.vtt + <lang>.m3u8,
     rewrite master.m3u8 with one EXT-X-MEDIA per language, and write review/epNN.md.
"""
import argparse, shutil, json, math, os, re, subprocess, sys, textwrap, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(os.path.dirname(HERE))
LANGS = [("en", "English"), ("pcm", "Naija Pidgin"), ("yo", "Yorùbá"), ("ig", "Igbo"), ("ha", "Hausa"), ("fr", "Français"), ("zh-Hans", "Chinese")]
LANG_NAMES = {"pcm": "Nigerian Pidgin", "yo": "Yoruba", "ig": "Igbo", "ha": "Hausa", "fr": "French", "zh-Hans": "Simplified Chinese (keep Latin names Felix/Ada/Lagos/DNA)"}
MAX_CHARS, MAX_LINES = 42, 2
CJK_MAX_CHARS = 18  # per line for zh-Hans
CJK_PUNCT = "，。！？；：…—、"


def is_cjk(text):
    return bool(re.search(r"[\u3000-\u9fff\uff00-\uffef]", text))


def line_limit(text):
    return CJK_MAX_CHARS if is_cjk(text) else MAX_CHARS
# ABR ladder (portrait 9:16). 360p first = startup rung on weak networks.
# (name, width, height, video bitrate, maxrate, bufsize, audio bitrate); audio AAC 48 kHz stereo on all rungs.
RENDITIONS = [
    ("360p", 360, 640, "800k", "880k", "1600k", "96k"),
    ("540p", 540, 960, "1200k", "1320k", "2400k", "128k"),
    ("720p", 720, 1280, "2500k", "2750k", "5000k", "128k"),
]
AUDIO_RATE = "48000"

TS = r"(?:(\d+):)?(\d{2}):(\d{2})[.,](\d{3})"


def to_ms(m):
    h, mi, s, ms = m
    return ((int(h or 0) * 60 + int(mi)) * 60 + int(s)) * 1000 + int(ms)


def fmt(ms):
    h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def parse_subs(path):
    """Parse SRT or WebVTT into [(start_ms, end_ms, text)]."""
    raw = open(path, encoding="utf-8-sig").read().replace("\r\n", "\n")
    cues = []
    for block in re.split(r"\n\s*\n", raw.strip()):
        lines = block.split("\n")
        for i, ln in enumerate(lines):
            m = re.match(rf"\s*{TS}\s*-->\s*{TS}", ln)
            if m:
                g = m.groups()
                text = " ".join(l.strip() for l in lines[i + 1:] if l.strip())
                cues.append((to_ms(g[:4]), to_ms(g[4:]), text))
                break
    if not cues:
        sys.exit(f"no cues in {path}")
    return cues


def wrap_cjk(text):
    if len(text) <= CJK_MAX_CHARS:
        return [text]
    mid = len(text) / 2
    cands = [i + 1 for i, ch in enumerate(text) if ch in CJK_PUNCT and i + 1 < len(text)]
    cands = [i for i in cands if i <= CJK_MAX_CHARS and len(text) - i <= CJK_MAX_CHARS] or [round(mid)]
    i = min(cands, key=lambda i: abs(i - mid))
    while i < len(text) and text[i] in CJK_PUNCT:  # keep trailing punctuation (e.g. "……") on line 1
        i += 1
    return [text[:i], text[i:]]


def wrap(text):
    if is_cjk(text):
        return wrap_cjk(text)
    lines = textwrap.wrap(text, MAX_CHARS, break_long_words=False)
    if len(lines) <= MAX_LINES:
        return lines
    # too long for 2x42: balance into 2 lines (flagged in review)
    words = text.split(); half = len(text) / 2; acc = 0
    for i, w in enumerate(words):
        acc += len(w) + 1
        if acc >= half:
            return [" ".join(words[: i + 1]), " ".join(words[i + 1:])]
    return lines


def write_vtt(path, cues, texts):
    out = ["WEBVTT", ""]
    for n, ((a, b, _), t) in enumerate(zip(cues, texts), 1):
        out += [str(n), f"{fmt(a)} --> {fmt(b)}", *wrap(t), ""]
    open(path, "w", encoding="utf-8").write("\n".join(out))


# ---------- translation providers ----------
def provider_manual(ep_dir, lang, src_texts):
    p = os.path.join(ep_dir, f"{lang}.json")
    if not os.path.exists(p):
        sys.exit(f"missing translation {p} (provide it or use --provider openai)")
    return json.load(open(p, encoding="utf-8"))


def provider_openai(ep_dir, lang, src_texts):
    key = os.environ.get("OPENAI_API_KEY") or sys.exit("OPENAI_API_KEY not set")
    prompt = (f"Translate these Nigerian family-comedy subtitle lines into {LANG_NAMES[lang]}. "
              "Keep names/proper nouns, keep it short for mobile subtitles, natural spoken register. "
              "Return ONLY a JSON array of strings with exactly the same number of items.\n" + json.dumps(src_texts, ensure_ascii=False))
    req = urllib.request.Request("https://api.openai.com/v1/chat/completions", method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                                 data=json.dumps({"model": os.environ.get("OPENAI_MODEL", "gpt-4o-mini"),
                                                  "messages": [{"role": "user", "content": prompt}]}).encode())
    content = json.load(urllib.request.urlopen(req, timeout=120))["choices"][0]["message"]["content"]
    texts = json.loads(content[content.index("["): content.rindex("]") + 1])
    os.makedirs(ep_dir, exist_ok=True)
    json.dump(texts, open(os.path.join(ep_dir, f"{lang}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return texts


PROVIDERS = {"manual": provider_manual, "openai": provider_openai}


# ---------- HLS ----------
# Fast start: 2s segments, closed GOP every 2s (aligned across renditions) so the
# player can start after ~one small 360p segment and ABR can switch every 2s.
SEG = 2
GOP = 60  # 2s @ 30fps (source is 30fps); force_key_frames guarantees a keyframe at every 2s boundary


def probe(path, entries, stream="v:0"):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", stream, "-show_entries", f"stream={entries}",
                          "-of", "default=nw=1", path], capture_output=True, text=True).stdout
    return dict(l.split("=", 1) for l in out.splitlines() if "=" in l)


def transcode(video, out_dir):
    for name, w, h, vb, mx, buf, ab in RENDITIONS:
        d = os.path.join(out_dir, name)
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", video, "-vf", f"scale={w}:{h},format=yuv420p",
                        "-c:v", "libx264", "-preset", "medium", "-profile:v", "main", "-b:v", vb, "-maxrate", mx, "-bufsize", buf,
                        "-g", str(GOP), "-keyint_min", str(GOP), "-sc_threshold", "0", "-force_key_frames", f"expr:gte(t,n_forced*{SEG})",
                        "-c:a", "aac", "-b:a", ab, "-ac", "2", "-ar", AUDIO_RATE,
                        "-f", "hls", "-hls_time", str(SEG), "-hls_playlist_type", "vod",
                        "-hls_segment_filename", os.path.join(d, "seg_%03d.ts"), os.path.join(d, "index.m3u8")], check=True)
    # drop rendition dirs that are no longer in the ladder (e.g. old src/)
    keep = {r[0] for r in RENDITIONS} | {"subs"}
    for x in os.listdir(out_dir):
        if os.path.isdir(os.path.join(out_dir, x)) and x not in keep:
            shutil.rmtree(os.path.join(out_dir, x))


def playlist_duration(out_dir):
    txt = open(os.path.join(out_dir, "720p", "index.m3u8")).read()
    return sum(float(x) for x in re.findall(r"#EXTINF:([\d.]+)", txt))


def rendition_stats(d):
    """Peak / average bits-per-second from actual segment sizes, plus resolution and RFC 6381 codec string."""
    txt = open(os.path.join(d, "index.m3u8")).read()
    segs = re.findall(r"#EXTINF:([\d.]+),\s*\n(\S+)", txt)
    rates = [os.path.getsize(os.path.join(d, f)) * 8 / float(t) for t, f in segs]
    tot = sum(os.path.getsize(os.path.join(d, f)) for _, f in segs) * 8 / sum(float(t) for t, _ in segs)
    first = os.path.join(d, segs[0][1])
    v = probe(first, "width,height,profile,level")
    prof = {"High": "6400", "Main": "4d40", "Constrained Baseline": "42e0", "Baseline": "4200"}[v["profile"]]
    a = probe(first, "profile", "a:0").get("profile", "LC")
    return {"peak": math.ceil(max(rates) * 1.05 / 1000) * 1000, "avg": math.ceil(tot / 1000) * 1000,
            "res": f'{v["width"]}x{v["height"]}', "codecs": f'avc1.{prof}{int(v["level"]):02x},mp4a.40.{5 if "HE" in a else 2}'}


def write_master(out_dir):
    lines = ["#EXTM3U", "#EXT-X-VERSION:3", "#EXT-X-INDEPENDENT-SEGMENTS"]
    for code, label in LANGS:
        lines.append(f'#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="{label}",LANGUAGE="{code}",'
                     f'DEFAULT=NO,AUTOSELECT=YES,FORCED=NO,URI="subs/{code}.m3u8"')
    for r in RENDITIONS:  # ladder order: 360p first (startup)
        name = r[0]
        st = rendition_stats(os.path.join(out_dir, name))
        lines += [f'#EXT-X-STREAM-INF:BANDWIDTH={st["peak"]},AVERAGE-BANDWIDTH={st["avg"]},RESOLUTION={st["res"]},'
                  f'FRAME-RATE=30.000,CODECS="{st["codecs"]}",SUBTITLES="subs"', f"{name}/index.m3u8"]
    open(os.path.join(out_dir, "master.m3u8"), "w").write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ep", type=int, required=True)
    ap.add_argument("--slug", default="mama-in-law-wahala")
    ap.add_argument("--src-dir", default="/workspace/naija-drama")
    ap.add_argument("--provider", default="manual", choices=PROVIDERS)
    ap.add_argument("--transcode", action="store_true", help="re-encode epNN_final.mp4 (or --video) to HLS")
    ap.add_argument("--video"); ap.add_argument("--en", help="source subtitle file")
    ap.add_argument("--source-lang", default="en", choices=[c for c, _ in LANGS], help="language of the source file (e.g. pcm)")
    a = ap.parse_args()
    nn = f"ep{a.ep:02d}"
    src = os.path.join(a.src_dir, nn)
    en = a.en or next((p for p in (os.path.join(src, f"{nn}_en.vtt"), os.path.join(src, "subs_en.srt")) if os.path.exists(p)), None)
    if not en:
        sys.exit(f"no EN source in {src}")
    out = os.path.join(BACKEND, "media", a.slug, f"ep{a.ep}")
    if a.transcode:
        video = a.video or os.path.join(src, f"{nn}_final.mp4")
        if not os.path.exists(video):
            sys.exit(f"video not found: {video}")
        print("transcoding", video); transcode(video, out)
    cues = parse_subs(en)
    src_texts = [c[2] for c in cues]
    tdir = os.path.join(HERE, "translations", nn)
    texts = {a.source_lang: src_texts}
    for code, _ in LANGS:
        if code == a.source_lang: continue
        t = PROVIDERS[a.provider](tdir, code, src_texts)
        if len(t) != len(cues):
            sys.exit(f"{code}: {len(t)} lines != {len(cues)} cues")
        texts[code] = t
    sub_dir = os.path.join(out, "subs"); os.makedirs(sub_dir, exist_ok=True)
    dur = playlist_duration(out)
    for code, _ in LANGS:
        write_vtt(os.path.join(sub_dir, f"{code}.vtt"), cues, texts[code])
        open(os.path.join(sub_dir, f"{code}.m3u8"), "w").write(
            f"#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:{math.ceil(dur)}\n#EXT-X-MEDIA-SEQUENCE:0\n"
            f"#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:{dur:.3f},\n{code}.vtt\n#EXT-X-ENDLIST\n")
    write_master(out)
    # review sheet
    os.makedirs(os.path.join(HERE, "review"), exist_ok=True)
    head = "| # | time | " + " | ".join(c for c, _ in LANGS) + " |"
    rows = [f"# {nn} subtitle review ({a.slug})", "", f"Source: `{en}` (lang `{a.source_lang}`, used as-is) · provider: `{a.provider}` · cues: {len(cues)}",
            "Lines marked ⚠ exceed 2×42 chars (2×18 for Chinese) after wrapping.", "", head, "|" + "---|" * (len(LANGS) + 2)]
    for i, (s, e, _) in enumerate(cues):
        cells = []
        for code, _ in LANGS:
            t = texts[code][i].replace("|", "\\|")
            if any(len(l) > line_limit(l) for l in wrap(texts[code][i])): t = "⚠ " + t
            cells.append(t)
        rows.append(f"| {i+1} | {fmt(s)[3:8]} | " + " | ".join(cells) + " |")
    open(os.path.join(HERE, "review", f"{nn}.md"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
    print(f"{nn}: {len(cues)} cues x {len(LANGS)} langs -> {sub_dir}")


if __name__ == "__main__":
    main()
