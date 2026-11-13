#!/usr/bin/env python3
"""Builds the AetherNX website into a folder (GitHub Pages: .github/workflows/pages.yml): the static files of site/, and from the game gallery
(docs/images/gallery.tsv, real captures of each game running in HorizonNative) and Studio's pages (docs/images/studio, studio/tools/snapshots.sh):
- a spine per game: the most detailed vertical slice of its capture, the shelf's spine; a WebP picture of the capture; its average colour
- WebP copies of Studio's pages
- the shelves written into index.html (no script needed to see them; site/app.js only pulls the spines)
Needs Pillow. Usage: site/tools/build.py <output folder>"""
import html, json, shutil, sys
from pathlib import Path
from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[2]
SITE, IMAGES = ROOT / 'site', ROOT / 'docs' / 'images'
REPO = 'https://github.com/iCosiSenpai/AetherNX'
SPINE_W, SPINE_H = 96, 540   # drawn at 48 x 270 CSS pixels


def games():
    out = []
    for line in (IMAGES / 'gallery.tsv').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'): continue
        image, name, note, tid = (line.split('\t') + ['', '', '', ''])[:4]
        if (IMAGES / image).is_file(): out.append({'image': image, 'name': name, 'note': note, 'tid': tid, 'switch2': tid.startswith('04')})
    return out


def spine(img):
    """The vertical slice with the most detail (grey-level spread), as a spine: SPINE_W x SPINE_H"""
    w, h = img.size
    sw = max(1, round(h * SPINE_W / SPINE_H))
    best, best_x = -1.0, (w - sw) // 2
    for i in range(11):
        x = round((w - sw) * i / 10)
        spread = ImageStat.Stat(img.crop((x, 0, x + sw, h)).convert('L')).stddev[0]
        if spread > best: best, best_x = spread, x
    return img.crop((best_x, 0, best_x + sw, h)).resize((SPINE_W, SPINE_H), Image.LANCZOS)


def colour(img):
    r, g, b = (round(v) for v in ImageStat.Stat(img.convert('RGB').resize((32, 18))).mean[:3])
    return f'#{r:02x}{g:02x}{b:02x}'


def spine_html(g, i, lead=False):
    note = html.escape(g['note'] or ('Switch 2' if g['switch2'] else 'Switch'))
    name = html.escape(g['name'])
    return (f'<li class="spine{" is-out" if lead else ""}" style="--c:{g["colour"]}" data-name="{name}" data-note="{note}" data-shot="{g["shot"]}" data-tid="{g["tid"]}"'
            f'{" data-switch2" if g["switch2"] else ""}><button type="button" aria-label="{name}: {note}"><img src="{g["spine"]}" alt="" width="48" height="270" loading="{"eager" if i < 48 else "lazy"}" decoding="async">'
            f'<span>{name}</span></button></li>')


def main(out):
    out = Path(out)
    if out.exists(): shutil.rmtree(out)
    shutil.copytree(SITE, out, ignore=shutil.ignore_patterns('tools', '*.md', '.DS_Store'))
    (out / 'g').mkdir(); (out / 'shots').mkdir()
    shelf = games()
    for g in shelf:
        stem = Path(g['image']).stem
        img = Image.open(IMAGES / g['image']).convert('RGB')
        spine(img).save(out / 'g' / f'{stem}-spine.webp', 'WEBP', quality=74, method=6)
        shot = img.copy(); shot.thumbnail((960, 540), Image.LANCZOS)
        shot.save(out / 'g' / f'{stem}.webp', 'WEBP', quality=78, method=6)
        g.update(spine=f'g/{stem}-spine.webp', shot=f'g/{stem}.webp', colour=colour(img))
    for png in sorted((IMAGES / 'studio').glob('*.png')):
        img = Image.open(png).convert('RGB')
        if img.width > 2000: img = img.resize((2000, round(img.height * 2000 / img.width)), Image.LANCZOS)
        img.save(out / 'shots' / f'{png.stem}.webp', 'WEBP', quality=84, method=6)
    lead = next((i for i, g in enumerate(shelf) if g['tid'] == '04007EF01F8AE000'), 0)
    # the hero's shelf: 44 games, the lead pulled out right of the middle, under its open case (the shelf is centred and cut at both edges)
    hero = [g for g in shelf if g is not shelf[lead]][:43]
    hero.insert(29, shelf[lead])
    page = (out / 'index.html').read_text(encoding='utf-8')
    page = page.replace('<!--SHELF-HERO-->', '\n'.join(spine_html(g, i, lead=g is shelf[lead]) for i, g in enumerate(hero)))
    page = page.replace('<!--SHELF-ALL-->', '\n'.join(spine_html(g, i + 99) for i, g in enumerate(shelf)))
    page = page.replace('{{GAMES}}', str(len(shelf))).replace('{{SWITCH2}}', str(sum(g['switch2'] for g in shelf)))
    page = page.replace('{{LEAD_SHOT}}', shelf[lead]['shot']).replace('{{LEAD_NAME}}', html.escape(shelf[lead]['name']))
    page = page.replace('{{LEAD_NOTE}}', html.escape(shelf[lead]['note'])).replace('{{VERSION}}', (ROOT / 'VERSION').read_text().strip())
    (out / 'index.html').write_text(page, encoding='utf-8')
    (out / 'games.json').write_text(json.dumps([{k: g[k] for k in ('name', 'note', 'tid', 'switch2', 'shot', 'spine', 'colour')} for g in shelf], ensure_ascii=False), encoding='utf-8')
    print(f'{len(shelf)} games, site in {out}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else ROOT / '_site')
