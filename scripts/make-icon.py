#!/usr/bin/env python3
"""Generate Earwig's app icon: a white soundwave + AI sparkle on a purple squircle.

Matches the app's `Theme.primaryGradient` (indigo -> purple). Renders a 1024px
master, then emits an .iconset and packs it into Resources/AppIcon.icns via
iconutil. Pure-Pillow so it's reproducible on any Mac.
"""
import math
import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 1024                      # master canvas size
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICONSET = os.path.join(HERE, "Earwig.iconset")
ICNS = os.path.join(ROOT, "Resources", "AppIcon.icns")

# App accent gradient (Theme.primaryGradient): indigo #5E5CE6 -> purple #9B5CF6,
# with the top lifted slightly for depth.
INDIGO_TOP = (110, 106, 240)  # lifted #6E6AF0
PURPLE_BOT = (155, 92, 246)   # #9B5CF6
WHITE = (255, 255, 255)
WHITE_DIM = (228, 226, 250)   # faint lavender-white for bar depth


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def superellipse_mask(size, margin, n=5.0):
    """A squircle (superellipse) alpha mask — Apple's app-icon silhouette."""
    mask = Image.new("L", (size, size), 0)
    px = mask.load()
    cx = cy = size / 2
    r = (size - 2 * margin) / 2
    for y in range(size):
        for x in range(size):
            dx = abs(x - cx) / r
            dy = abs(y - cy) / r
            if dx ** n + dy ** n <= 1.0:
                px[x, y] = 255
    return mask.filter(ImageFilter.GaussianBlur(0.6))


def diagonal_gradient(size, top, bot):
    """Top-left -> bottom-right gradient, echoing the app's primaryGradient direction."""
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = lerp(top, bot, t)
    return grad


def radial_glow(size, color, center, radius, peak_alpha):
    glow = Image.new("L", (size, size), 0)
    px = glow.load()
    cx, cy = center
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / radius
            if d < 1.0:
                px[x, y] = round(peak_alpha * (1 - d) ** 2)
    layer = Image.new("RGBA", (size, size), color + (0,))
    layer.putalpha(glow)
    return layer


def rounded_bar(draw, cx, height, width, color):
    """A vertical rounded-cap bar centred at cx on the canvas mid-line."""
    cy = S / 2
    x0, x1 = cx - width / 2, cx + width / 2
    y0, y1 = cy - height / 2, cy + height / 2
    draw.rounded_rectangle([x0, y0, x1, y1], radius=width / 2, fill=color)


def sparkle(draw, cx, cy, outer, inner, color):
    """A 4-point concave sparkle (the AI motif), centred at (cx, cy)."""
    pts = []
    for k in range(4):
        a_out = math.radians(90 * k - 90)   # N, E, S, W
        pts.append((cx + outer * math.cos(a_out), cy + outer * math.sin(a_out)))
        a_in = math.radians(90 * k - 45)    # inner waist between arms
        pts.append((cx + inner * math.cos(a_in), cy + inner * math.sin(a_in)))
    draw.polygon(pts, fill=color)


def build_master():
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Squircle body with the app's indigo -> purple gradient.
    body = diagonal_gradient(S, INDIGO_TOP, PURPLE_BOT).convert("RGBA")
    mask = superellipse_mask(S, margin=84)
    base.paste(body, (0, 0), mask)

    # Soft white glow behind the glyph for a luminous, premium feel.
    glow = radial_glow(S, WHITE, (S / 2, S * 0.54), radius=S * 0.40, peak_alpha=70)
    base = Image.alpha_composite(base, Image.composite(
        glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # White soundwave: five rounded bars, tallest in the centre — symmetric, "listening".
    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    heights = [250, 430, 560, 430, 250]
    width = 92
    gap = 150
    n = len(heights)
    start = S / 2 - (n - 1) * gap / 2
    for i, h in enumerate(heights):
        bar = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        rounded_bar(bd, start + i * gap, h, width, (255, 255, 255, 255))
        # Subtle top->bottom white -> faint-lavender for a hint of dimension.
        fill = Image.new("RGB", (S, S))
        fpx = fill.load()
        for y in range(S):
            c = lerp(WHITE, WHITE_DIM, y / (S - 1))
            for x in range(S):
                fpx[x, y] = c
        bar = Image.composite(fill.convert("RGBA"),
                              Image.new("RGBA", (S, S), (0, 0, 0, 0)), bar.split()[3])
        glyph = Image.alpha_composite(glyph, bar)

    # AI sparkles, lifted into the clear top-right space above the shorter bars.
    sd = ImageDraw.Draw(glyph)
    sparkle(sd, S * 0.785, S * 0.205, outer=S * 0.104, inner=S * 0.024, color=WHITE)
    sparkle(sd, S * 0.632, S * 0.120, outer=S * 0.046, inner=S * 0.011, color=WHITE)

    # Soft outer glow on the glyph itself, then the crisp glyph on top.
    glyph_glow = glyph.filter(ImageFilter.GaussianBlur(16))
    base = Image.alpha_composite(base, Image.composite(
        glyph_glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))
    base = Image.alpha_composite(base, glyph)

    # Glossy sheen: a bright, curved highlight over the top, clipped to the squircle.
    gloss = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(gloss)
    gd.ellipse([-S * 0.25, -S * 0.62, S * 1.25, S * 0.5], fill=60)
    gloss = gloss.filter(ImageFilter.GaussianBlur(4))
    gloss = Image.composite(gloss, Image.new("L", (S, S), 0), mask)
    sheen = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    sheen.putalpha(gloss)
    base = Image.alpha_composite(base, sheen)

    # Top rim highlight for a beveled, glassy edge.
    edge = mask.filter(ImageFilter.MaxFilter(9)).point(lambda v: 255 if v > 8 else 0)
    inner = mask.point(lambda v: 255 if v > 8 else 0)
    ring = ImageChops.subtract(edge, inner)
    top_fade = Image.new("L", (S, S), 0)
    tp = top_fade.load()
    for y in range(S):
        val = max(0, 130 - int(y / (S * 0.55) * 130))
        for x in range(S):
            tp[x, y] = val
    rim_alpha = ImageChops.multiply(ring, top_fade)
    rim = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    rim.putalpha(rim_alpha)
    base = Image.alpha_composite(base, rim)
    return base


def emit_iconset(master):
    os.makedirs(ICONSET, exist_ok=True)
    specs = [
        (16, "16x16"), (32, "16x16@2x"),
        (32, "32x32"), (64, "32x32@2x"),
        (128, "128x128"), (256, "128x128@2x"),
        (256, "256x256"), (512, "256x256@2x"),
        (512, "512x512"), (1024, "512x512@2x"),
    ]
    for px, name in specs:
        img = master.resize((px, px), Image.LANCZOS)
        img.save(os.path.join(ICONSET, f"icon_{name}.png"))
    os.makedirs(os.path.dirname(ICNS), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS], check=True)
    master.save(os.path.join(ROOT, "Resources", "AppIcon-preview.png"))
    print("Wrote", ICNS)


if __name__ == "__main__":
    emit_iconset(build_master())
