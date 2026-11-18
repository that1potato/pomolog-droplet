"""Draws Pomolog's icons and writes them into the package.

- Pomodorolog.icon: the droplet's own icon, a tomato with a summit flag.
- docs/icons/StickerBook.icon and docs/icons/History.icon: the tiles on the
  Settings links, a star sticker on an album and a clock turned back.
- Sources/Pomodorolog/Surfaces/SettingsTiles.swift: the two tiles rendered at
  56 x 56 pixels by Icon Composer's ictool, carried in the code.

Run from anywhere: python3 docs/icons/generator/icons.py [--preview DIR]
Needs Xcode 26 or later for ictool (or set ICTOOL to its path).
"""
import base64, json, math, os, shutil, subprocess, sys, tempfile, textwrap

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from geo import arc, capsule_line, radial, ring_arc, rounded, rrect, short_arc, star, svg

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ICTOOL = os.environ.get(
    "ICTOOL", "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")

TOMATO_STOPS = [(0, "#FF7A63"), (0.42, "#F2452F"), (1, "#D42E1E")]
LEAF = "#2DB24A"
POLE = "#8E8E93"
FLAG = "#3DA5F5"
PINK = "#FF5E8E"
BLUE = "#3A8DFF"
WHITE = "#FFFFFF"


def col(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def shift(pts, dx, dy):
    return [(x + dx, y + dy) for x, y in pts]


# ---------------------------------------------------------------- shapes

def tomato(c, rx, ry, n=2.06, dimple=0.07, top_flat=0.95):
    """A tomato's outline: a slightly squared ellipse, flatter on top, with a
    dip where the stem sits."""
    pts = []
    for i in range(360):
        t = 2 * math.pi * i / 360
        ct, st = math.cos(t), math.sin(t)
        x = rx * math.copysign(abs(ct) ** (2 / n), ct)
        y = ry * math.copysign(abs(st) ** (2 / n), st)
        if y < 0:
            y *= top_flat
        da = (t - 1.5 * math.pi + math.pi) % (2 * math.pi) - math.pi
        y += dimple * ry * math.exp(-(da / 0.3) ** 2)
        pts.append((c[0] + x, c[1] + y))
    return pts


def calyx(S, rx, ro_k=0.56, ri_k=0.16, squash=0.48, droop=0.16, rot=90):
    """The green star on top, seen from a little above: squashed, its sepals
    following the tomato's curve down."""
    ro, ri = rx * ro_k, rx * ri_k
    out = []
    for x, y in star((0, 0), ro, ri, n=5, rot=rot, r_tip=ro * 0.07, r_in=ri * 0.45):
        out.append((S[0] + x, S[1] + y * squash + droop * x * x / ro))
    return out


def polyline_stroke(p0, p1, p2, w):
    """Two joined strokes p0-p1-p2, width w, round caps and a round outer join."""
    h = w / 2

    def unit(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dy)
        return dx / l, dy / l

    d1, d2 = unit(p0, p1), unit(p1, p2)
    s = 1 if d1[0] * d2[1] - d1[1] * d2[0] > 0 else -1
    n1 = (s * d1[1], -s * d1[0])
    n2 = (s * d2[1], -s * d2[0])

    def off(p, n, k):
        return (p[0] + n[0] * h * k, p[1] + n[1] * h * k)

    a, b = off(p0, n1, -1), off(p1, n2, -1)
    den = d1[0] * d2[1] - d1[1] * d2[0]
    t = ((b[0] - a[0]) * d2[1] - (b[1] - a[1]) * d2[0]) / den
    inner = (a[0] + d1[0] * t, a[1] + d1[1] * t)
    pts = [off(p0, n1, 1), off(p1, n1, 1)]
    pts += short_arc(p1, h, off(p1, n1, 1), off(p1, n2, 1))[1:]
    pts.append(off(p2, n2, 1))
    a2 = math.atan2(n2[1], n2[0])
    pts += arc(p2, h, a2, a2 + s * math.pi)[1:]
    pts.append(inner)
    a1 = math.atan2(-n1[1], -n1[0])
    pts += arc(p0, h, a1, a1 + s * math.pi)
    return pts


# ---------------------------------------------------------------- icons

def droplet_icon():
    """A tomato with a summit flag planted where the stem goes, on cream.

    One layer, drawn back to front: Icon Composer puts its first group in
    front, while DroppyKit's flat preview draws groups in the order they are
    stored, so a single layer is the one way both agree."""
    c, rx, ry = (512, 632), 290, 256
    S = (c[0], c[1] - ry * 0.95 + ry * 0.07 + ry * 0.02)
    px = S[0] - 4
    pole = capsule_line((px, S[1] + 6), (px, 124), 24)
    pennant = rounded([(px + 6, 128), (px + 226, 198), (px + 6, 268)], [8, 22, 8])
    shading = radial("tomato", c[0] - rx * 0.38, c[1] - ry * 0.42, rx * 1.55, TOMATO_STOPS)
    art = svg([(tomato(c, rx, ry), "url(#tomato)"), (pole, POLE), (pennant, FLAG), (calyx(S, rx), LEAF)], defs=shading)
    doc = {
        "fill-specializations": [
            {"value": {"linear-gradient": [col("#FDF3E4"), col("#F2E7D6")]}},
            {"appearance": "dark", "value": {"linear-gradient": [col("#3A3A3C"), col("#1C1C1E")]}},
        ],
        "groups": [{
            "layers": [{"image-name": "pomolog.svg", "name": "pomolog"}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"squares": "shared"},
    }
    return doc, {"pomolog.svg": art}


def tile_doc(fill, image):
    return {
        "fill": {"automatic-gradient": col(fill)},
        "groups": [{
            "layers": [{"image-name": image, "name": image.rsplit(".", 1)[0]}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.5},
        }],
        "supported-platforms": {"squares": "shared"},
    }


def sticker_book_tile():
    """A closed album with a star sticker on its cover, white on pink."""
    x0, y0, x1, y1 = 304, 228, 720, 796
    spine_w, gap = 62, 30
    spine = rrect(x0, y0, x0 + spine_w, y1, [44, 14, 14, 44])
    cover = rrect(x0 + spine_w + gap, y0, x1, y1, [14, 64, 64, 14])
    sticker = star(((x0 + spine_w + gap + x1) / 2, (y0 + y1) / 2 + 6), 118, 58, r_tip=16, r_in=9)
    dx = 512 - (x0 + x1) / 2
    art = svg([(shift(spine, dx, 0), WHITE), ([shift(cover, dx, 0), shift(sticker, dx, 0)], WHITE, 1, True)])
    return tile_doc(PINK, "album.svg"), {"album.svg": art}


def history_tile():
    """A clock whose rim is an arrow turning back, white on blue."""
    c, rc, w = (512, 512), 268, 66
    a_tail, a_end, a_tip = math.radians(200), math.radians(-98), math.radians(-140)
    rim = ring_arc(c, rc, w, a_tail, a_end)
    tip = (c[0] + rc * math.cos(a_tip), c[1] + rc * math.sin(a_tip))
    hb = 100
    base_in = (c[0] + (rc - hb) * math.cos(a_end), c[1] + (rc - hb) * math.sin(a_end))
    base_out = (c[0] + (rc + hb) * math.cos(a_end), c[1] + (rc + hb) * math.sin(a_end))
    head = rounded([base_in, base_out, tip], [16, 16, 20])
    hour = (512 + 108 * math.cos(math.radians(30)), 512 + 108 * math.sin(math.radians(30)))
    hands = polyline_stroke((512, 512 - 142), (512, 512), hour, 60)
    art = svg([(rim, WHITE), (head, WHITE), (hands, WHITE)])
    return tile_doc(BLUE, "clock.svg"), {"clock.svg": art}


# ---------------------------------------------------------------- output

def write_icon(path, doc, assets):
    assets_dir = os.path.join(path, "Assets")
    if os.path.isdir(assets_dir):
        shutil.rmtree(assets_dir)
    os.makedirs(assets_dir)
    for name, text in assets.items():
        with open(os.path.join(assets_dir, name), "w") as fh:
            fh.write(text + "\n")
    with open(os.path.join(path, "icon.json"), "w") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")


def render(icon, out, points, rendition="Default"):
    subprocess.run([ICTOOL, icon, "--export-image", "--output-file", out, "--platform", "macOS",
                    "--rendition", rendition, "--width", str(points), "--height", str(points), "--scale", "2"],
                   check=True, stdout=subprocess.DEVNULL)


SWIFT = '''//
//  SettingsTiles.swift
//  Pomodorolog
//
//  Generated by docs/icons/generator/icons.py; regenerate, don't hand-edit.
//
//  The tiles on the Sticker book and History links in Settings: Icon
//  Composer's renders of docs/icons/StickerBook.icon and History.icon at 56 by
//  56 pixels, the size DroppyKit asks for. They are carried in the code rather
//  than in the bundle's Assets so the harness draws them too.
//

import AppKit

enum SettingsTiles {
    /// A star sticker on an album, white on pink.
    @MainActor static let stickerBook = tile(stickerBookPNG)
    /// A clock turned back, white on blue.
    @MainActor static let history = tile(historyPNG)

    /// A 56-pixel render as a 28-point image.
    private static func tile(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 28, height: 28)
        return image
    }

    private static let stickerBookPNG = """
{sticker}
        """

    private static let historyPNG = """
{history}
        """
}
'''


def b64(path):
    with open(path, "rb") as fh:
        text = base64.b64encode(fh.read()).decode()
    return "\n".join("        " + line for line in textwrap.wrap(text, 76))


def main():
    preview = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None

    write_icon(os.path.join(ROOT, "Pomodorolog.icon"), *droplet_icon())
    tiles = {
        "StickerBook": os.path.join(ROOT, "docs", "icons", "StickerBook.icon"),
        "History": os.path.join(ROOT, "docs", "icons", "History.icon"),
    }
    write_icon(tiles["StickerBook"], *sticker_book_tile())
    write_icon(tiles["History"], *history_tile())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for name, icon in tiles.items():
            pngs[name] = os.path.join(tmp, name + ".png")
            render(icon, pngs[name], 28)
        swift = SWIFT.replace("{sticker}", b64(pngs["StickerBook"])).replace("{history}", b64(pngs["History"]))
    with open(os.path.join(ROOT, "Sources", "Pomodorolog", "Surfaces", "SettingsTiles.swift"), "w") as fh:
        fh.write(swift)

    if preview:
        os.makedirs(preview, exist_ok=True)
        icon = os.path.join(ROOT, "Pomodorolog.icon")
        for pt in (128, 64, 28):
            render(icon, os.path.join(preview, f"pomolog-{pt}.png"), pt)
            render(icon, os.path.join(preview, f"pomolog-{pt}-dark.png"), pt, "Dark")
        for name, path in tiles.items():
            render(path, os.path.join(preview, f"{name}-112.png"), 112)
            render(path, os.path.join(preview, f"{name}-28.png"), 28)
    print("wrote Pomodorolog.icon, docs/icons/*.icon and SettingsTiles.swift")


if __name__ == "__main__":
    main()
