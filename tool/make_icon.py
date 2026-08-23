"""Draws the app icon: a rising line over volume bars, on a deep green ground."""
from PIL import Image, ImageDraw

S = 1024  # master size; every asset is downsampled from this


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def ground(size, radius_ratio=0.2237, top=(16, 62, 48), bottom=(6, 24, 20)):
    """Rounded square with a vertical gradient, matching the Android squircle."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(grad)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / (size - 1)) + (255,))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=round(size * radius_ratio), fill=255
    )
    img.paste(grad, (0, 0), mask)
    return img


def mark(size, inset=0.0):
    """The chart itself, drawn on a transparent square of `size`."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Work in a padded box so the mark never crowds the corners.
    pad = size * (0.185 + inset)
    left, right = pad, size - pad
    top, bottom = size * (0.245 + inset), size - size * (0.245 + inset)
    w, h = right - left, bottom - top

    green = (74, 222, 155)

    # Volume bars: four, rising, kept low so the line always clears them.
    heights = [0.20, 0.32, 0.26, 0.44]
    bar_w = w * 0.125
    gap = (w - bar_w * len(heights)) / (len(heights) - 1)
    for i, frac in enumerate(heights):
        x0 = left + i * (bar_w + gap)
        d.rounded_rectangle(
            [x0, bottom - h * frac, x0 + bar_w, bottom],
            radius=bar_w * 0.36,
            fill=green + (78,),
        )

    # The line: climbing left to right with one dip, so it reads as a market
    # rather than an arrow.
    pts = [
        (left, bottom - h * 0.30),
        (left + w * 0.34, bottom - h * 0.62),
        (left + w * 0.58, bottom - h * 0.50),
        (right, bottom - h * 0.94),
    ]

    # Area under the line, fading out towards the baseline.
    area = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(area).polygon(
        pts + [(right, bottom), (left, bottom)], fill=green + (255,)
    )
    alpha = area.split()[3].point(lambda v: 255 if v > 0 else 0)
    fade = Image.new("L", (size, size), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(size):
        t = min(max((y - top) / max(h, 1), 0.0), 1.0)
        fd.line([(0, y), (size, y)], fill=round(96 * (1 - t) ** 1.2))
    area.putalpha(Image.composite(fade, Image.new("L", (size, size), 0), alpha))
    img.alpha_composite(area)

    stroke = size * 0.066
    d.line(pts, fill=green + (255,), width=round(stroke), joint="curve")
    # Round the ends, which `line` leaves square.
    for x, y in (pts[0], pts[-1]):
        r = stroke / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=green + (255,))

    # The apex, marked the way the charts in the app mark their latest point.
    x, y = pts[-1]
    r = size * 0.070
    d.ellipse([x - r, y - r, x + r, y + r], fill=green + (255,))
    r2 = size * 0.029
    d.ellipse([x - r2, y - r2, x + r2, y + r2], fill=(6, 24, 20, 255))
    return img


def full(size):
    img = ground(size)
    img.alpha_composite(mark(size))
    return img


master = full(S)
master.save("assets/icon/app_icon.png")

# Android legacy launcher icons.
for name, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    full(S).resize((px, px), Image.LANCZOS).save(
        f"android/app/src/main/res/mipmap-{name}/ic_launcher.png"
    )

# Adaptive icon: the mark alone on a transparent 108dp canvas, drawn inside the
# 72dp safe zone so no launcher mask can clip it.
for name, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
    fg = mark(S, inset=0.085)
    fg.resize((px, px), Image.LANCZOS).save(
        f"android/app/src/main/res/mipmap-{name}/ic_launcher_foreground.png"
    )

print("wrote", master.size)
