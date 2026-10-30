"""Generate NaijaReels launcher icons (legacy + adaptive) and a preview sheet from the v20 eagle.

Source: assets/branding/icon_v20_final.png (1024x1024, brand green #00A859 calibrated)
Mask:   assets/branding/icon_v20_fg_mask.png (alpha matte of the eagle; made once with rembg
        isnet-general-use + ellipse for the green body, so this script needs only Pillow).
Usage:  python3 tool/gen_launcher_icons.py [preview_out]
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
HERE = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.join(HERE, '..', 'assets', 'branding')
SRC, MASK = os.path.join(BRAND, 'icon_v20_final.png'), os.path.join(BRAND, 'icon_v20_fg_mask.png')
BG = (0, 0xA8, 0x59)
RES = os.path.join(HERE, '..', 'android', 'app', 'src', 'main', 'res')
DENS = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
W = 1536            # master 108dp canvas (1dp = W/108 px)
SAFE_R = 32.0       # keep every opaque pixel (incl. white outline) within r=32dp (< 33dp safe zone)
STROKE = 1.6        # white outline width in dp, separates the green body from the green background

def _master():
    src = Image.open(SRC).convert('RGB'); m = Image.open(MASK).convert('L')
    eagle = src.convert('RGBA'); eagle.putalpha(m)
    bb = m.point(lambda v: 255 if v > 24 else 0).getbbox(); eagle = eagle.crop(bb)
    # find radius of the farthest opaque pixel from the eagle bbox centre to size it into the safe circle
    a = eagle.split()[3].resize((eagle.width // 4, eagle.height // 4)); px = a.load()
    cx, cy = a.width / 2, a.height / 2
    r = max(((x - cx) ** 2 + (y - cy) ** 2) ** .5 for y in range(a.height) for x in range(a.width) if px[x, y] > 24) * 4
    dp = W / 108; scale = (SAFE_R - STROKE) * dp / r
    eagle = eagle.resize((round(eagle.width * scale), round(eagle.height * scale)), Image.LANCZOS)
    fg = Image.new('RGBA', (W, W), (0, 0, 0, 0)); fg.alpha_composite(eagle, ((W - eagle.width) // 2, (W - eagle.height) // 2))
    al = fg.split()[3]; k = int(STROKE * dp) * 2 + 1
    halo = al.filter(ImageFilter.MaxFilter(k if k % 2 else k + 1)).filter(ImageFilter.GaussianBlur(1.5))
    out = Image.new('RGBA', (W, W), (255, 255, 255, 0)); out.putalpha(halo); out.alpha_composite(fg)
    return out

FG = None
def fg_master():
    global FG
    if FG is None: FG = _master()
    return FG

def fg(px): return fg_master().resize((px, px), Image.LANCZOS)

def mono(px):
    a = fg_master().split()[3].resize((px, px), Image.LANCZOS)
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0)); black = Image.new('RGBA', (px, px), (0, 0, 0, 255))
    out.paste(black, (0, 0), a); return out

def bgimg(px): return Image.new('RGBA', (px, px), BG + (255,))

def full_layer(n):  # 108dp composed layer at n px
    l = bgimg(n); l.alpha_composite(fg(n)); return l

def shaped(px, shape, margin=0.0):
    """Viewport (central 72dp of 108dp) of the composed layer under a mask."""
    SS = 4; n = px * SS; full = round(n * 108 / 72); off = (full - n) // 2
    crop = full_layer(full).crop((off, off, off + n, off + n))
    mask = Image.new('L', (n, n), 0); md = ImageDraw.Draw(mask); m = n * margin; box = [m, m, n - m, n - m]
    if shape == 'circle': md.ellipse(box, fill=255)
    elif shape == 'squircle': md.rounded_rectangle(box, radius=(n - 2 * m) * 0.28, fill=255)
    else:  # teardrop: round except bottom-right corner
        md.ellipse(box, fill=255); md.rectangle([n / 2, n / 2, n - m, n - m], fill=255)
    out = Image.new('RGBA', (n, n), (0, 0, 0, 0)); out.paste(crop, (0, 0), mask)
    return out.resize((px, px), Image.LANCZOS)

def main():
    for d, s in DENS.items():
        p = os.path.join(RES, f'mipmap-{d}'); os.makedirs(p, exist_ok=True)
        shaped(int(48 * s), 'squircle', 0.04).save(f'{p}/ic_launcher.png', optimize=True)
        shaped(int(48 * s), 'circle', 0.04).save(f'{p}/ic_launcher_round.png', optimize=True)
        fg(int(108 * s)).save(f'{p}/ic_launcher_foreground.png', optimize=True)
        bgimg(int(108 * s)).save(f'{p}/ic_launcher_background.png', optimize=True)
        mono(int(108 * s)).save(f'{p}/ic_launcher_monochrome.png', optimize=True)
    os.makedirs(f'{RES}/values', exist_ok=True)
    open(f'{RES}/values/ic_launcher_background.xml', 'w').write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#00A859</color>\n</resources>\n')
    os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@color/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n</adaptive-icon>\n')
    for nm in ('ic_launcher', 'ic_launcher_round'):
        open(f'{RES}/mipmap-anydpi-v26/{nm}.xml', 'w').write(xml)
    if len(sys.argv) > 1: preview(sys.argv[1])

def font(sz):
    for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',):
        if os.path.exists(f): return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

def homescreen(im, x, y, w, h, dark):
    wp = Image.new('RGBA', (w, h)); wd = ImageDraw.Draw(wp)
    for yy in range(h):
        c = (18, 22 + yy // 14, 40 + yy // 9, 255) if dark else (232 - yy // 20, 238 - yy // 25, 246, 255)
        wd.line([(0, yy), (w, yy)], fill=c)
    im.alpha_composite(wp, (x, y)); d = ImageDraw.Draw(im)
    tc = (235, 235, 235) if dark else (30, 30, 30)
    d.text((x + 12, y + 10), ('Dark' if dark else 'Light') + ' home screen (48dp @ xxhdpi + 1x)', fill=tc, font=font(16))
    others = [(66, 133, 244), None, (234, 67, 53), (251, 188, 5)]
    for i, lab in enumerate(['Phone', 'NaijaReels', 'Mail', 'Files']):
        cx = x + 30 + i * 135
        if lab == 'NaijaReels': im.alpha_composite(shaped(96, 'circle'), (cx, y + 50))
        else: d.ellipse([cx, y + 50, cx + 96, y + 146], fill=others[i])
        f = font(16); tw = d.textlength(lab, font=f); d.text((cx + 48 - tw / 2, y + 152), lab, fill=tc, font=f)
    # actual-size row (48px = mdpi 48dp) and 72px
    for j, s in enumerate((48, 72)):
        im.alpha_composite(shaped(s, 'circle'), (x + 30 + j * 110, y + 190))
        d.text((x + 30 + j * 110, y + 192 + s), f'{s}px', fill=tc, font=font(13))

def preview(path):
    Wd, Ht = 1450, 960; im = Image.new('RGBA', (Wd, Ht), (245, 245, 245, 255)); d = ImageDraw.Draw(im)
    d.text((30, 20), 'NaijaReels launcher icon v20 (adaptive, bg #00A859)', fill=(20, 20, 20), font=font(30))
    x = 30
    for sh, lab in (('circle', 'Circle'), ('squircle', 'Rounded square'), ('teardrop', 'Teardrop')):
        im.alpha_composite(shaped(220, sh), (x, 80)); d.text((x, 310), lab, fill=(60, 60, 60), font=font(20)); x += 260
    im.alpha_composite(full_layer(220), (x, 80)); d = ImageDraw.Draw(im)
    s = 220 / 108; d.rectangle([x + 18 * s, x * 0 + 80 + 18 * s, x + 90 * s, 80 + 90 * s], outline=(255, 255, 255))
    d.ellipse([x + 21 * s, 80 + 21 * s, x + 87 * s, 80 + 87 * s], outline=(255, 0, 0), width=2)
    d.text((x, 310), '108dp, red=66dp safe', fill=(60, 60, 60), font=font(16)); x += 260
    m = mono(220); bgm = Image.new('RGBA', (220, 220), (225, 230, 240, 255)); bgm.alpha_composite(m)
    im.alpha_composite(bgm, (x, 80)); d.text((x, 310), 'Monochrome', fill=(60, 60, 60), font=font(20))
    homescreen(im, 30, 370, 680, 300, True); homescreen(im, 740, 370, 680, 300, False)
    d = ImageDraw.Draw(im); x = 30
    for dn in DENS:
        ic = Image.open(f'{RES}/mipmap-{dn}/ic_launcher.png'); rc = Image.open(f'{RES}/mipmap-{dn}/ic_launcher_round.png')
        im.alpha_composite(ic, (x, 690)); im.alpha_composite(rc, (x + ic.width + 8, 690))
        d.text((x, 690 + ic.height + 4), f'{dn} {ic.width}px', fill=(60, 60, 60), font=font(13)); x += ic.width * 2 + 40
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True); im.convert('RGB').save(path)

if __name__ == '__main__': main()
