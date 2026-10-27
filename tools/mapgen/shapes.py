"""Province outlines and triangles from a label raster, with shared borders.

Every boundary between two provinces (or a province and the sea) is traced once along pixel edges, cut into
chains at junctions, simplified once (Douglas-Peucker), and reused by both sides, so neighbours meet exactly:
no gaps, no overlaps. Rings are rebuilt per province, holes (lakes, enclaves) bridged in, and every polygon
triangulated by ear clipping. Coordinates are map pixels.
"""

from __future__ import annotations

import math
from collections import defaultdict

import numpy as np

EPS_BORDER = 1.2  # px tolerance between two provinces (Voronoi borders are nearly straight anyway)
EPS_COAST = 2.5  # px tolerance along coasts, which carry most of the vertices
MIN_ISLAND = 150.0  # px²: smaller islands are not drawn (they still belong to their province)
MIN_HOLE = 12.0  # px²: smaller lakes are filled in


# ------------------------------------------------------------------------------------------- tracing


def boundary_chains(labels: np.ndarray):
    """Chains of pixel-corner vertices along every label boundary: list of (a, b, [(x, y), ...])."""
    h, w = labels.shape
    pad = np.full((h + 2, w + 2), -1, dtype=np.int64)
    pad[1:-1, 1:-1] = labels
    edges = []  # (v0, v1, a, b) with a < b
    # vertical edges: between pad[y, x-1] and pad[y, x]; corner coords (x, y)-(x, y+1)
    left, right = pad[:, :-1], pad[:, 1:]
    ys, xs = np.nonzero(left != right)
    for y, x in zip(ys.tolist(), xs.tolist()):
        a, b = int(left[y, x]), int(right[y, x])
        edges.append(((x + 1, y), (x + 1, y + 1), min(a, b), max(a, b)))
    up, down = pad[:-1, :], pad[1:, :]
    ys, xs = np.nonzero(up != down)
    for y, x in zip(ys.tolist(), xs.tolist()):
        a, b = int(up[y, x]), int(down[y, x])
        edges.append(((x, y + 1), (x + 1, y + 1), min(a, b), max(a, b)))

    incident = defaultdict(list)
    for i, (v0, v1, _, _) in enumerate(edges):
        incident[v0].append(i)
        incident[v1].append(i)

    def is_junction(v) -> bool:
        inc = incident[v]
        if len(inc) != 2:
            return True
        e0, e1 = edges[inc[0]], edges[inc[1]]
        return (e0[2], e0[3]) != (e1[2], e1[3])

    used = [False] * len(edges)
    chains = []

    def walk(start_v, first_edge):
        pts = [start_v]
        e = first_edge
        v = start_v
        a, b = edges[e][2], edges[e][3]
        while True:
            used[e] = True
            v0, v1 = edges[e][0], edges[e][1]
            v = v1 if v0 == v else v0
            pts.append(v)
            if is_junction(v) or v == start_v:
                break
            nxt = [i for i in incident[v] if not used[i]]
            if not nxt:
                break
            e = nxt[0]
        return a, b, pts

    for v, inc in list(incident.items()):
        if is_junction(v):
            for e in inc:
                if not used[e]:
                    chains.append(walk(v, e))
    for e in range(len(edges)):
        if not used[e]:  # closed loop with no junction (an island coast, an enclave)
            chains.append(walk(edges[e][0], e))
    return [(a, b, [(x - 1, y - 1) for x, y in pts]) for a, b, pts in chains]


# ------------------------------------------------------------------------------------------- simplify


def _dp(points, eps):
    if len(points) <= 2:
        return list(points)
    pts = np.asarray(points, dtype=np.float64)
    keep = np.zeros(len(pts), dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        seg = b - a
        seglen = math.hypot(*seg)
        mid = pts[i + 1 : j]
        if seglen < 1e-9:
            d = np.hypot(mid[:, 0] - a[0], mid[:, 1] - a[1])
        else:
            d = np.abs(seg[0] * (mid[:, 1] - a[1]) - seg[1] * (mid[:, 0] - a[0])) / seglen
        k = int(np.argmax(d))
        if d[k] > eps:
            m = i + 1 + k
            keep[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return [tuple(p) for p in pts[keep].tolist()]


def simplify_chain(pts, eps):
    if pts[0] == pts[-1] and len(pts) > 3:
        # closed loop: anchor at the point farthest from the start, simplify both halves
        arr = np.asarray(pts[:-1], dtype=np.float64)
        far = int(np.argmax(np.hypot(arr[:, 0] - arr[0, 0], arr[:, 1] - arr[0, 1])))
        first = _dp(pts[: far + 1], eps)
        second = _dp(pts[far:], eps)
        out = first + second[1:]
        return out if len(out) >= 4 else pts
    return _dp(pts, eps)


# ------------------------------------------------------------------------------------------- rings


def signed_area(ring) -> float:
    s = 0.0
    n = len(ring)
    for i in range(n):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % n]
        s += x0 * y1 - x1 * y0
    return s / 2


def point_in_ring(p, ring) -> bool:
    x, y = p
    inside = False
    n = len(ring)
    for i in range(n):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            t = (y - y0) / (y1 - y0)
            if x < x0 + t * (x1 - x0):
                inside = not inside
    return inside


def ring_inside(r, other) -> bool:
    """Is ring r inside ring other? Tested with a vertex of r that is not on other (rings share junctions)."""
    on_other = set(other)
    for p in r:
        if p not in on_other:
            return point_in_ring(p, other)
    return False


def assemble_rings(chains_of_province):
    """Join a province's chains end to end into closed rings."""
    at = defaultdict(list)
    for idx, pts in enumerate(chains_of_province):
        at[pts[0]].append(idx)
        at[pts[-1]].append(idx)
    used = [False] * len(chains_of_province)
    rings = []
    for start in range(len(chains_of_province)):
        if used[start]:
            continue
        used[start] = True
        ring = list(chains_of_province[start])
        if ring[0] == ring[-1] and len(ring) > 2:
            rings.append(ring[:-1])
            continue
        guard = 0
        while ring[-1] != ring[0] and guard < 100000:
            guard += 1
            end = ring[-1]
            nxt = next((i for i in at[end] if not used[i]), None)
            if nxt is None:
                break
            used[nxt] = True
            pts = chains_of_province[nxt]
            if pts[0] != end:
                pts = pts[::-1]
            ring.extend(pts[1:])
        if ring[0] == ring[-1]:
            ring = ring[:-1]
        if len(ring) >= 3:
            rings.extend(split_at_repeats(ring))
    return rings


def split_at_repeats(ring):
    """A province touching itself at one corner gives a figure-8 ring; cut it into simple loops."""
    out = []
    stack = []
    seen = {}
    for p in ring:
        if p in seen:
            start = seen[p]
            loop = stack[start:]
            for q in loop[1:]:
                seen.pop(q, None)
            del stack[start + 1 :]
            if len(loop) >= 3:
                out.append(loop)
        else:
            seen[p] = len(stack)
            stack.append(p)
    if len(stack) >= 3:
        out.append(stack)
    return out


# ------------------------------------------------------------------------------------------- triangulate


def _cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def _strictly_inside(p, a, b, c):
    """p inside the counter-clockwise triangle abc, not on its edges or corners."""
    return _cross(a, b, p) > 1e-9 and _cross(b, c, p) > 1e-9 and _cross(c, a, p) > 1e-9


def _segments_cross(p1, p2, q1, q2):
    d1, d2 = _cross(q1, q2, p1), _cross(q1, q2, p2)
    d3, d4 = _cross(p1, p2, q1), _cross(p1, p2, q2)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)) and d1 * d2 < 0 and d3 * d4 < 0


def bridge_holes(outer, holes):
    """Merge holes into the outer ring with zero-width bridges (outer CCW, holes CW in math orientation)."""
    poly = list(outer)
    for hole in sorted(holes, key=lambda h: -max(p[0] for p in h)):
        hi = max(range(len(hole)), key=lambda i: hole[i][0])
        hp = hole[hi]
        all_edges = [(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly))]
        best, best_d = None, math.inf
        for j, op in enumerate(poly):
            d = (op[0] - hp[0]) ** 2 + (op[1] - hp[1]) ** 2
            if d >= best_d:
                continue
            if any(_segments_cross(hp, op, e0, e1) for e0, e1 in all_edges if op not in (e0, e1)):
                continue
            best, best_d = j, d
        if best is None:
            best = min(range(len(poly)), key=lambda j: (poly[j][0] - hp[0]) ** 2 + (poly[j][1] - hp[1]) ** 2)
        hole_seq = hole[hi:] + hole[: hi + 1]
        poly = poly[: best + 1] + hole_seq + [poly[best]] + poly[best + 1 :]
    return poly


def ear_clip(poly):
    """Triangulate a simple polygon (counter-clockwise in math orientation). Returns index-free triangles."""
    pts = list(poly)
    tris = []
    n = len(pts)
    if n < 3:
        return tris
    idx = list(range(n))
    guard = 0
    while len(idx) > 3 and guard < 20 * n * n:
        guard += 1
        found = False
        m = len(idx)
        for k in range(m):
            i0, i1, i2 = idx[(k - 1) % m], idx[k], idx[(k + 1) % m]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if _cross(a, b, c) <= 1e-12:
                continue  # reflex or flat
            ok = True
            for j in idx:
                if j in (i0, i1, i2):
                    continue
                if _strictly_inside(pts[j], a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((a, b, c))
                del idx[k]
                found = True
                break
        if not found:
            # degenerate leftovers (from simplification): drop the flattest vertex and move on
            m = len(idx)
            k = min(range(m), key=lambda k: abs(_cross(pts[idx[(k - 1) % m]], pts[idx[k]], pts[idx[(k + 1) % m]])))
            del idx[k]
    if len(idx) == 3:
        a, b, c = (pts[i] for i in idx)
        if abs(_cross(a, b, c)) > 1e-12:
            tris.append((a, b, c) if _cross(a, b, c) > 0 else (a, c, b))
    return tris


# ------------------------------------------------------------------------------------------- API


def province_shapes(labels: np.ndarray, n: int):
    """Returns (shapes, borders).

    shapes[i] = {"tris": [[x0, y0, x1, y1, x2, y2], ...], "rings": [[(x, y), ...], ...], "area": px²}
    borders = [{"a": i, "b": j, "points": [(x, y), ...]}] for every simplified border between two provinces.
    """
    chains = boundary_chains(labels)
    simplified = []
    for a, b, pts in chains:
        eps = EPS_COAST if a == -1 else EPS_BORDER
        simplified.append((a, b, simplify_chain(pts, eps)))

    by_province = defaultdict(list)
    borders = []
    for a, b, pts in simplified:
        if a >= 0:
            by_province[a].append(pts)
        by_province[b].append(pts)
        if a >= 0 and len(pts) >= 2:
            borders.append({"a": a, "b": b, "points": pts})

    shapes = []
    for i in range(n):
        rings = assemble_rings(by_province.get(i, []))
        # math orientation: y grows downwards in the image, so flip the sign to get the usual CCW = positive
        rings = [r if -signed_area(r) > 0 else r[::-1] for r in rings]
        areas = [-signed_area(r) for r in rings]
        outers, holes = [], []
        for r, area in zip(rings, areas):
            contained = sum(1 for other in rings if other is not r and ring_inside(r, other)) % 2 == 1
            (holes if contained else outers).append((r, area))
        tris = []
        total = 0.0
        kept_rings = []
        largest = max((a for _, a in outers), default=0.0)
        for outer, area in outers:
            if area < MIN_ISLAND and area < largest:
                continue  # drop specks, but never a province's main piece
            my_holes = [h[::-1] for h, ha in holes if ha >= MIN_HOLE and ring_inside(h, outer)]
            poly = bridge_holes(outer, my_holes)
            # ear_clip wants counter-clockwise in math orientation: flip y for the test, back for output
            flipped = [(x, -y) for x, y in poly]
            for t in ear_clip(flipped):
                tris.append([round(c, 2) for p in t for c in (p[0], -p[1])])
            total += area - sum(abs(signed_area(h)) for h in my_holes)
            kept_rings.append(outer)
        shapes.append({"tris": tris, "rings": kept_rings, "area": total})
    return shapes, borders


def triangles_area(tris) -> float:
    s = 0.0
    for t in tris:
        s += abs((t[2] - t[0]) * (t[5] - t[1]) - (t[4] - t[0]) * (t[3] - t[1])) / 2
    return s
