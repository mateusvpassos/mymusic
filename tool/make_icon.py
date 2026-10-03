"""Gera o ícone do app (assets/icon/*.png). Rodar: python tool/make_icon.py
Depois: dart run flutter_launcher_icons"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import os

S = 4  # supersampling
N = 1024 * S
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon')
FONT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts', 'JetBrainsMono-Bold.ttf')


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background():
    """Gradiente diagonal índigo -> roxo, com brilho leve em cima."""
    a, b = (99, 102, 241), (76, 29, 149)  # indigo-500 -> violet-900
    g = Image.linear_gradient('L').resize((N * 2, N * 2)).rotate(45, resample=Image.BICUBIC)
    g = g.crop((N // 2, N // 2, N // 2 + N, N // 2 + N))
    base = Image.composite(Image.new('RGB', (N, N), b), Image.new('RGB', (N, N), a), g)
    glow = Image.new('L', (N, N), 0)
    ImageDraw.Draw(glow).ellipse([-N * .2, -N * .45, N * .9, N * .45], fill=55)
    glow = glow.filter(ImageFilter.GaussianBlur(N * .1))
    return Image.composite(Image.new('RGB', (N, N), (224, 231, 255)), base, glow)


def rrect(d, box, r, fill):
    d.rounded_rectangle([int(v) for v in box], radius=int(r), fill=fill)


def page(mono=False):
    """Folha de cifra: acordes coloridos sobre linhas de letra."""
    L = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    u = N / 1024
    w, h = 400 * u, 470 * u
    x0, y0 = (N - w) / 2, (N - h) / 2 + 6 * u

    # folha de trás (repertório)
    back = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    rrect(ImageDraw.Draw(back), [x0, y0, x0 + w, y0 + h], 44 * u,
          (255, 255, 255, 255) if mono else (199, 210, 254, 255))
    back = back.rotate(9, resample=Image.BICUBIC, center=(N / 2, N / 2))
    if not mono:
        # sombra
        sh = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        rrect(ImageDraw.Draw(sh), [x0, y0 + 26 * u, x0 + w, y0 + h + 26 * u], 44 * u, (20, 10, 60, 110))
        sh = sh.filter(ImageFilter.GaussianBlur(28 * u))
        L = Image.alpha_composite(L, sh)
    L = Image.alpha_composite(L, back)

    front = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(front)
    rrect(d, [x0, y0, x0 + w, y0 + h], 44 * u, (255, 255, 255, 255))
    hole = (0, 0, 0, 0)
    font = ImageFont.truetype(FONT, int(54 * u))
    chords = [('C', (245, 158, 11)), ('G', (16, 185, 129)), ('Am', (236, 72, 153))]
    pad = 52 * u
    ys = [y0 + 58 * u, y0 + 198 * u, y0 + 338 * u]
    offs = [0, 120 * u, 40 * u]
    for (name, col), y, ox in zip(chords, ys, offs):
        tw = d.textlength(name, font=font)
        px = x0 + pad + ox
        box = [px, y, px + tw + 40 * u, y + 66 * u]
        if mono:
            rrect(d, box, 20 * u, hole)
        else:
            rrect(d, box, 20 * u, col + (255,))
            d.text((px + 20 * u, y + 33 * u), name, font=font, anchor='lm', fill=(255, 255, 255, 255))
        ly = y + 86 * u
        lw = w - 2 * pad - (0 if ox == 0 else 30 * u)
        rrect(d, [x0 + pad, ly, x0 + pad + lw, ly + 22 * u], 11 * u,
              hole if mono else (71, 85, 105, 255))
    if mono:
        # Pillow não "fura" com alpha 0 no draw normal: refaz como máscara
        m = Image.new('L', (N, N), 0)
        md = ImageDraw.Draw(m)
        rrect(md, [x0, y0, x0 + w, y0 + h], 44 * u, 255)
        for (name, _), y, ox in zip(chords, ys, offs):
            tw = d.textlength(name, font=font)
            px = x0 + pad + ox
            rrect(md, [px, y, px + tw + 40 * u, y + 66 * u], 20 * u, 0)
            ly = y + 86 * u
            lw = w - 2 * pad - (0 if ox == 0 else 30 * u)
            rrect(md, [x0 + pad, ly, x0 + pad + lw, ly + 22 * u], 11 * u, 0)
        front = Image.new('RGBA', (N, N), (255, 255, 255, 0))
        front.putalpha(m)
        bm = back.getchannel('A')
        solida = Image.new('L', (N, N), 0)
        rrect(ImageDraw.Draw(solida), [x0, y0, x0 + w, y0 + h], 44 * u, 255)
        bm = ImageChops.subtract(bm, solida.filter(ImageFilter.MaxFilter(4 * 9 + 1)))
        L = Image.new('RGBA', (N, N), (255, 255, 255, 0))
        L.putalpha(ImageChops.lighter(bm, m))
        return L.rotate(-4, resample=Image.BICUBIC, center=(N / 2, N / 2))
    front = front.rotate(-4, resample=Image.BICUBIC, center=(N / 2, N / 2))
    return Image.alpha_composite(L, front.rotate(0))


def scaled(img, k):
    """Encolhe o conteúdo p/ caber na zona segura do ícone adaptativo."""
    small = img.resize((int(N * k), int(N * k)), Image.LANCZOS)
    out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    o = (N - small.width) // 2
    if o < 0:
        return small.crop((-o, -o, -o + N, -o + N))
    out.paste(small, (o, o), small)
    return out


def save(img, name):
    img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name))


bg = background()
fg = page()
save(bg, 'background.png')
save(scaled(fg, 0.95), 'foreground.png')
save(scaled(page(mono=True), 0.95), 'monochrome.png')
full = bg.convert('RGBA')
full = Image.alpha_composite(full, scaled(fg, 1.15))
save(full, 'icon.png')
print('ok')
