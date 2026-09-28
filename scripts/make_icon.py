"""Draws the Snipsy app icon (crayon scissors in a selection frame) into the asset catalog.

    python3 scripts/make_icon.py        # needs Pillow + numpy

Coordinates are in a 512-unit design space, rendered at 1024 px.
"""
import json, math, pathlib, random
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

K = 2                      # 512 design units -> 1024 px
S = 512 * K
OUT = pathlib.Path(__file__).resolve().parent.parent / "app/Snipsy/Assets.xcassets/AppIcon.appiconset"
rng = random.Random(7)
np_rng = np.random.default_rng(7)


def u(v):
    return v * K


def mask():
    return Image.new("L", (S, S))


def crayon(m, rgb, n=5000, grain=0.2, angle=-0.45):
    """Fill mask `m` with short jittered diagonal strokes plus paper grain."""
    layer = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = m.getbbox()
    for _ in range(int(n * K)):
        x, y = rng.uniform(x0 - u(20), x1 + u(20)), rng.uniform(y0 - u(20), y1 + u(20))
        a = angle + rng.uniform(-0.15, 0.15)
        length = u(rng.uniform(15, 55))
        dx, dy = length * math.cos(a), length * math.sin(a)
        c = tuple(max(0, min(255, v + rng.randint(-18, 18))) for v in rgb)
        d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=c + (rng.randint(110, 210),), width=u(rng.randint(3, 6)))
    a = np.asarray(layer).astype(float)
    a[..., 3] *= (np.asarray(m).astype(float) / 255) * (np_rng.random((S, S)) > grain)
    return Image.fromarray(a.astype(np.uint8))


def outline(m, rgb, w=9):
    edge = ImageChops.subtract(m.filter(ImageFilter.MaxFilter(u(w) + 1)), m.filter(ImageFilter.MinFilter(3)))
    return crayon(edge, rgb, n=5000, grain=0.35)


def jitter(p, j=3):
    return (p[0] + u(rng.uniform(-j, j)), p[1] + u(rng.uniform(-j, j)))


img = Image.new("RGBA", (S, S))

# Tile: Apple's macOS grid puts the rounded square at ~80% of the canvas, with a soft shadow.
tile = mask()
ImageDraw.Draw(tile).rounded_rectangle((u(50), u(50), u(462), u(462)), u(92), fill=255)
shadow = Image.new("RGBA", (S, S), (40, 30, 20, 0))
shadow.putalpha(tile.point(lambda v: v * 0.35).filter(ImageFilter.GaussianBlur(u(10))))
img.alpha_composite(shadow, (0, u(6)))
img.alpha_composite(Image.composite(Image.new("RGBA", (S, S), (245, 239, 227, 255)), Image.new("RGBA", (S, S)), tile))
img.alpha_composite(crayon(tile, (236, 228, 212), n=2000, grain=0.5))
img.alpha_composite(outline(tile, (170, 164, 150), w=6))

# Blue selection corners
corners = mask()
d = ImageDraw.Draw(corners)
a, b, L = 104, 408, 70
for cx, cy, sx, sy in [(a, a, 1, 1), (b, a, -1, 1), (a, b, 1, -1), (b, b, -1, -1)]:
    pts = [(cx, cy + sy * L), (cx, cy), (cx + sx * L, cy)]
    d.line([jitter((u(x), u(y))) for x, y in pts], fill=255, width=u(18), joint="curve")
img.alpha_composite(crayon(corners, (104, 144, 200), n=3000, grain=0.2))

# Scissors: two blades opening up-right, orange ring handles down-left.
pivot = np.array([262.0, 250.0])
blades, handles = mask(), mask()
db, dh = ImageDraw.Draw(blades), ImageDraw.Draw(handles)
for deg in (-65, -15):
    t = math.radians(deg)
    dvec = np.array([math.cos(t), math.sin(t)])
    n = np.array([-dvec[1], dvec[0]])
    tip, back = pivot + dvec * 150, pivot - dvec * 18
    poly = [pivot + n * 11, tip, pivot - n * 11, back]
    db.polygon([jitter((u(p[0]), u(p[1])), 2) for p in poly], fill=255)
    # handle on the opposite side of the pivot
    hvec = -dvec
    center = pivot + hvec * 112
    dh.line([(u(pivot[0]), u(pivot[1])), (u(center[0] - hvec[0] * 36), u(center[1] - hvec[1] * 36))], fill=255, width=u(20))
    r_out, r_in = 40, 23
    dh.ellipse([u(center[0] - r_out), u(center[1] - r_out), u(center[0] + r_out), u(center[1] + r_out)], fill=255)
    dh.ellipse([u(center[0] - r_in), u(center[1] - r_in), u(center[0] + r_in), u(center[1] + r_in)], fill=0)
img.alpha_composite(crayon(blades, (150, 160, 176), n=3500, grain=0.12))
img.alpha_composite(outline(blades, (92, 100, 116), w=6))
img.alpha_composite(crayon(handles, (222, 110, 64), n=5000, grain=0.12))
img.alpha_composite(outline(handles, (178, 78, 40), w=7))

screw = mask()
ImageDraw.Draw(screw).ellipse([u(pivot[0] - 10), u(pivot[1] - 10), u(pivot[0] + 10), u(pivot[1] + 10)], fill=255)
img.alpha_composite(crayon(screw, (60, 50, 45), n=600, grain=0.05))

# Asset catalog: every macOS size, 1x and 2x.
OUT.mkdir(parents=True, exist_ok=True)
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        img.resize((pt * scale, pt * scale), Image.LANCZOS).save(OUT / name)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
(OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
print("wrote", OUT)
