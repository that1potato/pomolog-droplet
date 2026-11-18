"""Small geometry kit for icon glyphs on a 1024 canvas: filleted polygons,
discs cut by a chord, caps, rings, capsules. Every shape comes out as a dense
point list so no SVG arc flag can go wrong."""
import math

STEP = math.radians(1.5)


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s != "-0" else "0"


def path(pts):
    if not pts:
        return ""
    d = [f"M{fmt(pts[0][0])},{fmt(pts[0][1])}"]
    d += [f"L{fmt(x)},{fmt(y)}" for x, y in pts[1:]]
    return " ".join(d) + " Z"


def arc(c, r, a0, a1, step=STEP):
    """Points on a circle from angle a0 to a1 (radians), in that direction."""
    n = max(2, int(abs(a1 - a0) / step) + 1)
    return [(c[0] + r * math.cos(a0 + (a1 - a0) * i / (n - 1)),
             c[1] + r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def short_arc(c, r, p, q, step=STEP):
    a0 = math.atan2(p[1] - c[1], p[0] - c[0])
    a1 = math.atan2(q[1] - c[1], q[0] - c[0])
    d = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
    return arc(c, r, a0, a0 + d, step)


def circle(c, r):
    return arc(c, r, 0, 2 * math.pi)[:-1]


def ellipse(c, rx, ry, rot=0.0, n=240):
    cr, sr = math.cos(rot), math.sin(rot)
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        out.append((c[0] + x * cr - y * sr, c[1] + x * sr + y * cr))
    return out


def rounded(pts, radii):
    """A polygon with each corner filleted (radius per corner or one for all)."""
    n = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * n
    out = []
    for i in range(n):
        P, A, B = pts[i], pts[i - 1], pts[(i + 1) % n]
        ux, uy = A[0] - P[0], A[1] - P[1]
        vx, vy = B[0] - P[0], B[1] - P[1]
        la, lb = math.hypot(ux, uy), math.hypot(vx, vy)
        ux, uy, vx, vy = ux / la, uy / la, vx / lb, vy / lb
        ang = math.acos(max(-1.0, min(1.0, ux * vx + uy * vy)))
        r = radii[i]
        if r <= 0 or ang > math.pi - 1e-3:
            out.append(P)
            continue
        t = min(r / math.tan(ang / 2), la * 0.5, lb * 0.5)
        r = t * math.tan(ang / 2)
        bx, by = ux + vx, uy + vy
        bl = math.hypot(bx, by)
        h = r / math.sin(ang / 2)
        C = (P[0] + bx / bl * h, P[1] + by / bl * h)
        T1 = (P[0] + ux * t, P[1] + uy * t)
        T2 = (P[0] + vx * t, P[1] + vy * t)
        out += short_arc(C, r, T1, T2)
    return out


def star(c, ro, ri, n=5, rot=-90.0, r_tip=0.0, r_in=0.0):
    pts = []
    for k in range(2 * n):
        r = ro if k % 2 == 0 else ri
        a = math.radians(rot + k * 180.0 / n)
        pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))
    return rounded(pts, [r_tip if k % 2 == 0 else r_in for k in range(2 * n)])


def rrect(x0, y0, x1, y1, r):
    if isinstance(r, (int, float)):
        r = [r] * 4
    return rounded([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], list(r))


def capsule_line(p, q, w):
    """A stroke from p to q, width w, round caps."""
    a = math.atan2(q[1] - p[1], q[0] - p[0])
    h = w / 2
    return arc(q, h, a - math.pi / 2, a + math.pi / 2) + arc(p, h, a + math.pi / 2, a + 3 * math.pi / 2)


def disc_minus_cap(c, R, ang, d, rho):
    """The disc of radius R at c with the cap beyond the chord at distance d
    (normal at angle `ang`) cut off; both chord corners filleted by rho."""
    u = (math.cos(ang), math.sin(ang))
    v = (-u[1], u[0])
    s = math.sqrt((R - rho) ** 2 - (d - rho) ** 2)
    def P(a, b):
        return (c[0] + a * u[0] + b * v[0], c[1] + a * u[1] + b * v[1])
    cf_p, cf_m = (d - rho, s), (d - rho, -s)
    k = R / (R - rho)
    A_p, A_m = P(cf_p[0] * k, cf_p[1] * k), P(cf_m[0] * k, cf_m[1] * k)
    L_p, L_m = P(d, s), P(d, -s)
    Cp, Cm = P(*cf_p), P(*cf_m)
    a_p = math.atan2(A_p[1] - c[1], A_p[0] - c[0])
    a_m = math.atan2(A_m[1] - c[1], A_m[0] - c[0])
    # long way from A+ round the far side to A-
    sweep = (a_m - a_p) % (2 * math.pi)
    # the long arc must avoid the cap direction
    mid = a_p + sweep / 2
    if math.cos(mid - ang) > 0:
        sweep -= 2 * math.pi
    pts = arc(c, R, a_p, a_p + sweep)
    pts += short_arc(Cm, rho, A_m, L_m)
    pts += short_arc(Cp, rho, L_p, A_p)
    return pts


def cap(c, R, ang, d, rho):
    """The cap of the disc (R at c) beyond the chord at distance d, normal at
    `ang`; corners filleted by rho."""
    u = (math.cos(ang), math.sin(ang))
    v = (-u[1], u[0])
    s = math.sqrt((R - rho) ** 2 - (d + rho) ** 2)
    def P(a, b):
        return (c[0] + a * u[0] + b * v[0], c[1] + a * u[1] + b * v[1])
    k = R / (R - rho)
    C1, C2 = P(d + rho, s), P(d + rho, -s)
    A1, A2 = P((d + rho) * k, s * k), P((d + rho) * k, -s * k)
    L1, L2 = P(d, s), P(d, -s)
    a1 = math.atan2(A1[1] - c[1], A1[0] - c[0])
    a2 = math.atan2(A2[1] - c[1], A2[0] - c[0])
    dd = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
    pts = short_arc(C1, rho, L1, A1)
    pts += arc(c, R, a1, a1 + dd)
    pts += short_arc(C2, rho, A2, L2)
    return pts


def ring_arc(c, r, w, a0, a1):
    """A thick arc (stroke width w) from a0 to a1 with round ends."""
    ro, ri = r + w / 2, r - w / 2
    outer = arc(c, ro, a0, a1)
    end = (c[0] + r * math.cos(a1), c[1] + r * math.sin(a1))
    start = (c[0] + r * math.cos(a0), c[1] + r * math.sin(a0))
    sgn = 1 if a1 > a0 else -1
    cap_end = arc(end, w / 2, a1, a1 + sgn * math.pi)
    inner = arc(c, ri, a1, a0)
    cap_start = arc(start, w / 2, a0 + sgn * math.pi, a0 + sgn * 2 * math.pi)
    return outer + cap_end + inner + cap_start


def radial(id, cx, cy, r, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<radialGradient id="{id}" gradientUnits="userSpaceOnUse" cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}">{s}</radialGradient>'


def svg(layers, size=1024, defs=""):
    """layers: list of (pts or path-string, fill, opacity, evenodd)."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">']
    if defs:
        out.append(f"<defs>{defs}</defs>")
    for item in layers:
        shape, fill = item[0], item[1]
        op = item[2] if len(item) > 2 else 1
        rule = ' fill-rule="evenodd"' if (len(item) > 3 and item[3]) else ""
        d = shape if isinstance(shape, str) else (
            " ".join(path(s) for s in shape) if shape and isinstance(shape[0], list) else path(shape))
        o = f' fill-opacity="{op}"' if op != 1 else ""
        out.append(f'<path d="{d}" fill="{fill}"{o}{rule}/>')
    out.append("</svg>")
    return "\n".join(out)
