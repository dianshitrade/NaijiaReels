"""Generate NaijaReels launcher icons (legacy + adaptive) and a preview sheet. Usage: python3 tool/gen_launcher_icons.py [preview_out]"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
G1, G2 = (0, 0xA8, 0x59), (0, 0x6B, 0x3A)
RES = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
SS = 4

def grad(n):
    im = Image.new('RGB', (n, n)); px = im.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(G1, G2))
    return im

def tri(d, cx, cy, h, color):
    # rounded-ish play triangle, visually centred: shift right by ~h*0.06
    w = h * 0.88; cx += h * 0.08
    pts = [(cx - w / 2, cy - h / 2), (cx - w / 2, cy + h / 2), (cx + w / 2, cy)]
    d.polygon(pts, fill=color)
    r = h * 0.07
    d.line(pts + [pts[0]], fill=color, width=int(r * 2), joint='curve')
    for p in pts: d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)

def legacy(px, round_):
    n = px * SS; m = n * 0.04  # small margin like stock icons
    bg = grad(n); mask = Image.new('L', (n, n), 0); md = ImageDraw.Draw(mask)
    box = [m, m, n - m, n - m]
    if round_: md.ellipse(box, fill=255)
    else: md.rounded_rectangle(box, radius=(n - 2 * m) * 0.28, fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.paste(bg, (0, 0), mask)
    tri(ImageDraw.Draw(out), n / 2, n / 2, n * 0.40, (255, 255, 255, 255))
    return out.resize((px, px), Image.LANCZOS)

def fg(px, color=(255, 255, 255, 255)):  # 108dp canvas, glyph inside central 66dp
    n = px * SS; out = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    tri(ImageDraw.Draw(out), n / 2, n / 2, n * 0.30, color)  # ~32dp tall, well inside 66dp
    return out.resize((px, px), Image.LANCZOS)

def bgimg(px): return grad(px * SS).resize((px, px), Image.LANCZOS)

def main():
    for d, s in DENS.items():
        p = os.path.join(RES, f'mipmap-{d}'); os.makedirs(p, exist_ok=True)
        legacy(int(48 * s), False).save(f'{p}/ic_launcher.png', optimize=True)
        legacy(int(48 * s), True).save(f'{p}/ic_launcher_round.png', optimize=True)
        fg(int(108 * s)).save(f'{p}/ic_launcher_foreground.png', optimize=True)
        bgimg(int(108 * s)).save(f'{p}/ic_launcher_background.png', optimize=True)
        fg(int(108 * s), (0, 0, 0, 255)).save(f'{p}/ic_launcher_monochrome.png', optimize=True)
    os.makedirs(f'{RES}/values', exist_ok=True)
    open(f'{RES}/values/ic_launcher_background.xml', 'w').write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#00A859</color>\n</resources>\n')
    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n</adaptive-icon>\n')
    for nm in ('ic_launcher', 'ic_launcher_round'):
        open(f'{RES}/mipmap-anydpi-v26/{nm}.xml', 'w').write(xml)
    if len(sys.argv) > 1: preview(sys.argv[1])

def adaptive(px, shape):
    n = px * SS; full = int(n * 108 / 72); off = (full - n) // 2
    layer = grad(full).convert('RGBA'); layer.alpha_composite(fg(full // SS).resize((full, full)))
    crop = layer.crop((off, off, off + n, off + n))
    mask = Image.new('L', (n, n), 0); md = ImageDraw.Draw(mask)
    if shape == 'circle': md.ellipse([0, 0, n, n], fill=255)
    elif shape == 'squircle': md.rounded_rectangle([0, 0, n, n], radius=n * 0.3, fill=255)
    else:  # teardrop: round except bottom-right corner
        md.ellipse([0, 0, n, n], fill=255); md.rectangle([n / 2, n / 2, n, n], fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.paste(crop, (0, 0), mask)
    return out.resize((px, px), Image.LANCZOS)

def font(sz):
    for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def preview(path):
    W, H = 1400, 900; im = Image.new('RGBA', (W, H), (245, 245, 245, 255)); d = ImageDraw.Draw(im)
    d.text((30, 20), 'NaijaReels launcher icon', fill=(20, 20, 20), font=font(36))
    x = 30
    for dn in DENS:
        for j, nm in enumerate(('ic_launcher', 'ic_launcher_round')):
            ic = Image.open(f'{RES}/mipmap-{dn}/{nm}.png')
            im.alpha_composite(ic, (x, 90 + j * 210 + (192 - ic.height)))
        d.text((x, 500), f'{dn} {ic.width}px', fill=(60, 60, 60), font=font(18)); x += max(ic.width, 110) + 60
    x = 30
    for sh in ('circle', 'squircle', 'teardrop'):
        im.alpha_composite(adaptive(160, sh), (x, 560)); d.text((x, 730), f'adaptive/{sh}', fill=(60, 60, 60), font=font(18)); x += 200
    # mock home screen
    hx, hy, hw, hh = 680, 540, 690, 340
    wp = Image.new('RGBA', (hw, hh)); wd = ImageDraw.Draw(wp)
    for y in range(hh): wd.line([(0, y), (hw, y)], fill=(20, 24 + y // 12, 48 + y // 8, 255))
    wp = wp.filter(ImageFilter.GaussianBlur(2)); im.alpha_composite(wp, (hx, hy)); d = ImageDraw.Draw(im)
    others = [(66, 133, 244), (234, 67, 53), (251, 188, 5)]
    for i in range(4):
        cx = hx + 60 + i * 160
        ic = adaptive(96, 'circle') if i == 1 else None
        if ic is None:
            c = others[i if i == 0 else i - 1]; d.ellipse([cx, hy + 90, cx + 96, hy + 186], fill=c)
            lab = ['Phone', '', 'Mail', 'Files'][i]
        else: im.alpha_composite(ic, (cx, hy + 90)); lab = 'NaijaReels'
        f = font(20); tw = d.textlength(lab, font=f); d.text((cx + 48 - tw / 2, hy + 196), lab, fill='white', font=f)
    d.text((hx + 10, hy + 10), 'mock home screen', fill=(200, 200, 200), font=font(16))
    os.makedirs(os.path.dirname(path), exist_ok=True); im.convert('RGB').save(path)

main()
