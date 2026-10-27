"""Earth: the real world, 1:1 coastlines, 150 provinces named after geographic regions.

Coastlines come from Natural Earth (public domain) via the world-atlas package
(data/land-50m.json). Projection: Miller cylindrical, centred on 11°E so the
Americas sit on the left, Asia on the right and the Bering Strait wraps around.

Province and nation names are geographic or historic regions, never modern
countries, which keeps the map clear of touchy borders.
"""

from __future__ import annotations

import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

from layout import (
    Layout,
    Seed,
    assign_start_territories,
    auto_connect,
    balance_start_development,
    build_regions,
    curated_straits,
    finalize,
)

W, H = 2048, 1024
WEST = -169.0  # left edge longitude (map spans WEST .. WEST + 360)
NORTH = 83.6
DATA = os.path.join(os.path.dirname(__file__), "..", "data", "land-50m.json")


def miller(lat: float) -> float:
    return 1.25 * math.log(math.tan(math.pi / 4 + 0.4 * math.radians(lat)))


Y_TOP = miller(NORTH)
PX_PER_RAD = W / (2 * math.pi)


def project(lon: float, lat: float) -> tuple[float, float]:
    if lon < WEST:
        lon += 360.0
    return _project_raw(lon, lat)


def _project_raw(lon: float, lat: float) -> tuple[float, float]:
    x = (lon - WEST) / 360.0 * W
    y = (Y_TOP - miller(max(min(lat, 89.0), -89.0))) * PX_PER_RAD
    return x, y


def land_mask(ss: int = 2) -> np.ndarray:
    """Rasterise Natural Earth land (minus Antarctica) with ss x supersampling."""
    with open(DATA) as f:
        topo = json.load(f)
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    arcs = []
    for arc in topo["arcs"]:
        a = np.cumsum(np.array(arc, dtype=np.float64), axis=0)
        arcs.append(np.stack([a[:, 0] * sx + tx, a[:, 1] * sy + ty], axis=1))

    def ring_coords(ring):
        pts = []
        for idx in ring:
            seg = arcs[idx] if idx >= 0 else arcs[~idx][::-1]
            pts.extend(seg[1:] if pts else seg)
        return np.array(pts)

    img = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    for geom in topo["objects"]["land"]["geometries"]:
        polys = geom["arcs"] if geom["type"] == "MultiPolygon" else [geom["arcs"]]
        for poly in polys:
            for k, ring in enumerate(poly):
                c = ring_coords(ring)
                if c[:, 1].max() < -60:  # Antarctica
                    continue
                lon = c[:, 0].copy()
                if lon.max() - lon.min() > 300:  # ring crosses the antimeridian (e.g. Eurasia with Chukotka)
                    lon[lon < -150] += 360.0
                elif lon.mean() < WEST:
                    lon += 360.0
                pts = [(x, y) for x, y in (_project_raw(lo, la) for lo, la in zip(lon, c[:, 1]))]
                pts = [(x * ss, y * ss) for x, y in pts]
                if len(pts) >= 3:
                    d.polygon(pts, fill=255 if k == 0 else 0)
    img = img.resize((W, H), Image.BOX)
    return np.asarray(img) >= 128


# name, lat, lon, biome, nation (start capitals only)
REGIONS = [
    # Europe
    ("Iceland", 64.9, -18.6, "tundra"),
    ("Scotland", 57.0, -4.3, "hills"),
    ("England", 52.6, -1.6, "grassland"),
    ("Seine", 48.6, 2.4, "grassland"),
    ("Aquitaine", 44.6, 0.3, "grassland"),
    ("Provence", 43.9, 5.6, "hills"),
    ("Lusitania", 39.6, -8.0, "grassland"),
    ("Castile", 40.6, -3.8, "steppe"),
    ("Andalusia", 37.6, -4.6, "drylands"),
    ("Alps", 46.9, 9.0, "mountains"),
    ("Lombardy", 45.0, 11.0, "grassland"),
    ("Latium", 42.2, 12.8, "hills"),
    ("Low Countries", 52.0, 5.3, "grassland"),
    ("Rhineland", 50.3, 8.0, "grassland", "Rhine"),
    ("Bavaria", 48.6, 11.8, "forest"),
    ("Bohemia", 49.9, 15.2, "hills"),
    ("Vistula", 52.2, 19.8, "grassland"),
    ("Jutland", 56.0, 9.3, "grassland"),
    ("Norway", 61.5, 8.5, "hills"),
    ("Sweden", 59.8, 15.5, "taiga"),
    ("Finland", 63.0, 26.5, "taiga"),
    ("Baltic", 57.0, 24.5, "forest"),
    ("Pannonia", 47.2, 19.4, "grassland"),
    ("Transylvania", 46.0, 24.8, "hills"),
    ("Balkans", 43.3, 23.0, "hills"),
    ("Hellas", 39.6, 22.0, "hills"),
    ("Dnieper", 50.0, 31.0, "grassland"),
    ("Pontic Steppe", 46.8, 35.0, "steppe"),
    ("Muscovy", 55.8, 37.8, "forest", "Volga"),
    ("White Sea", 64.0, 40.5, "taiga"),
    ("Lower Volga", 50.0, 45.5, "steppe"),
    ("Urals", 58.0, 59.0, "hills"),
    # Middle East
    ("Anatolia", 39.0, 32.5, "drylands"),
    ("Caucasus", 42.8, 44.0, "mountains"),
    ("Armenian Highland", 39.8, 43.0, "hills"),
    ("Levant", 33.0, 36.2, "drylands"),
    ("Mesopotamia", 33.2, 44.0, "steppe", "Tigris"),
    ("Hejaz", 23.5, 40.0, "desert"),
    ("Najd", 24.5, 46.0, "desert"),
    ("Yemen", 15.5, 45.5, "hills"),
    ("Zagros", 33.5, 48.5, "mountains"),
    ("Persis", 30.0, 53.5, "drylands"),
    ("Khorasan", 35.5, 59.0, "drylands"),
    ("Bactria", 37.0, 65.0, "hills"),
    ("Hindu Kush", 35.0, 71.0, "mountains"),
    # North and Central Asia
    ("Ob", 61.0, 72.0, "taiga"),
    ("Yenisei", 64.0, 92.0, "taiga"),
    ("Altai", 50.0, 88.0, "mountains"),
    ("Baikal", 54.0, 107.0, "taiga"),
    ("Lena", 64.0, 125.0, "taiga"),
    ("Amur", 50.5, 132.0, "taiga"),
    ("Kamchatka", 57.0, 160.0, "hills"),
    ("Chukotka", 66.5, 172.0, "tundra"),
    ("Kazakh Steppe", 48.5, 67.0, "steppe"),
    ("Turan", 41.0, 61.0, "desert"),
    ("Dzungaria", 44.5, 85.0, "steppe"),
    ("Pamir", 38.5, 72.5, "mountains"),
    # South Asia
    ("Punjab", 30.5, 73.5, "grassland"),
    ("Indus Delta", 25.5, 68.5, "desert"),
    ("Ganges Plain", 26.0, 82.0, "grassland", "Ganges"),
    ("Bengal", 23.5, 89.5, "jungle"),
    ("Deccan", 18.5, 77.0, "savanna"),
    ("Dravida", 11.5, 78.0, "savanna"),
    ("Lanka", 7.8, 80.7, "jungle"),
    ("Himalaya", 28.8, 84.5, "mountains"),
    ("Tibet", 32.5, 88.5, "mountains"),
    ("Karakoram", 35.5, 77.0, "mountains"),
    # East Asia
    ("Yangtze Valley", 30.5, 114.5, "grassland", "Yangtze"),
    ("Yellow River", 35.5, 113.0, "grassland"),
    ("Manchuria", 45.5, 126.0, "forest"),
    ("Mongolia", 47.5, 103.0, "steppe"),
    ("Gobi", 42.5, 108.0, "desert"),
    ("Korea", 37.0, 127.5, "hills"),
    ("Yamato", 36.0, 138.5, "hills"),
    ("Ezo", 43.3, 142.8, "forest"),
    ("Formosa", 23.7, 121.0, "hills"),
    ("Sichuan", 30.5, 104.0, "hills"),
    ("Lingnan", 23.5, 112.5, "forest"),
    ("Tarim", 39.5, 82.0, "desert"),
    # Southeast Asia
    ("Mekong", 15.0, 104.0, "savanna", "Mekong"),
    ("Irrawaddy", 20.0, 96.0, "jungle"),
    ("Tonkin", 21.5, 105.0, "hills"),
    ("Malaya", 4.5, 102.0, "jungle"),
    ("Sumatra", -0.5, 101.5, "jungle"),
    ("Java", -7.3, 110.0, "grassland"),
    ("Borneo", 1.0, 114.0, "jungle"),
    ("Luzon", 15.5, 121.0, "jungle"),
    ("New Guinea", -5.0, 141.0, "jungle"),
    # Oceania
    ("Westralia", -26.0, 121.0, "desert"),
    ("Outback", -24.0, 134.0, "desert"),
    ("Top End", -14.5, 133.0, "savanna"),
    ("Queensland", -21.0, 145.5, "savanna"),
    ("Murray", -33.5, 146.0, "grassland"),
    ("Aotearoa", -41.5, 173.0, "hills"),
    # Africa
    ("Atlas", 32.0, -6.0, "hills"),
    ("Numidia", 35.5, 4.5, "hills"),
    ("Tripolitania", 31.0, 14.0, "desert"),
    ("Nile Delta", 30.0, 31.0, "grassland"),
    ("Nubia", 19.0, 32.0, "desert"),
    ("Hoggar", 23.5, 5.0, "desert"),
    ("Senegambia", 13.8, -15.0, "savanna"),
    ("Niger Bend", 14.5, -3.5, "savanna", "Niger"),
    ("Hausaland", 12.0, 8.0, "savanna"),
    ("Lake Chad", 13.5, 16.5, "savanna"),
    ("Guinea Coast", 7.5, -6.0, "jungle"),
    ("Niger Delta", 6.0, 6.5, "jungle"),
    ("Abyssinia", 9.5, 39.0, "hills"),
    ("Horn", 6.0, 46.5, "drylands"),
    ("Congo", 0.0, 22.0, "jungle"),
    ("Great Lakes", -1.5, 31.5, "hills"),
    ("Swahili Coast", -6.5, 37.5, "savanna"),
    ("Benguela", -12.5, 17.0, "savanna"),
    ("Zambezi", -15.0, 28.0, "savanna", "Zambezi"),
    ("Sofala", -19.0, 34.5, "savanna"),
    ("Kalahari", -23.0, 21.5, "desert"),
    ("Cape", -30.0, 24.5, "drylands"),
    ("Madagascar", -19.5, 46.8, "jungle"),
    # North America
    ("Alaska", 64.5, -152.0, "tundra"),
    ("Cascadia", 47.0, -121.0, "forest"),
    ("California", 37.5, -120.0, "grassland"),
    ("Great Basin", 40.0, -115.5, "desert"),
    ("Rockies", 43.0, -108.5, "mountains"),
    ("Sonora", 29.5, -110.5, "desert"),
    ("Anahuac", 19.5, -100.0, "hills"),
    ("Yucatan", 19.0, -89.5, "jungle"),
    ("Isthmus", 12.0, -85.5, "jungle"),
    ("Texas", 31.0, -98.5, "steppe"),
    ("Great Plains", 41.5, -99.0, "grassland"),
    ("Mississippi", 36.5, -89.5, "grassland", "Mississippi"),
    ("Appalachia", 36.5, -80.5, "forest"),
    ("New England", 43.5, -72.5, "forest"),
    ("Prairies", 52.5, -108.0, "grassland"),
    ("Canadian Shield", 51.0, -88.0, "taiga"),
    ("Laurentia", 50.5, -71.0, "taiga"),
    ("Hudson", 63.0, -96.0, "tundra"),
    ("Greenland", 72.0, -40.0, "ice"),
    ("Antilles", 21.7, -79.5, "jungle"),
    # South America
    ("Llanos", 6.5, -68.5, "savanna"),
    ("Guiana", 4.5, -58.5, "jungle"),
    ("Northern Andes", 3.5, -75.0, "hills"),
    ("Amazonia", -3.5, -62.0, "jungle", "Amazon"),
    ("Cusco", -11.0, -75.0, "hills"),
    ("Altiplano", -17.5, -67.5, "mountains"),
    ("Atacama", -24.0, -69.5, "desert"),
    ("Araucania", -37.5, -72.5, "hills"),
    ("Patagonia", -46.0, -69.0, "steppe"),
    ("Pampas", -34.5, -61.5, "grassland"),
    ("Mato Grosso", -13.5, -55.0, "savanna"),
    ("Sertao", -8.5, -40.5, "savanna"),
    ("Atlantic Forest", -21.5, -45.0, "forest"),
]

STRAITS = [
    ("Iceland", "Scotland"),
    ("Iceland", "Greenland"),
    ("Greenland", "Laurentia"),
    ("England", "Seine"),
    ("Jutland", "Sweden"),
    ("Latium", "Numidia"),  # Sicily to Tunis
    ("Andalusia", "Atlas"),  # Gibraltar
    ("Balkans", "Anatolia"),  # Bosporus
    ("Hellas", "Anatolia"),  # Aegean
    ("Yemen", "Horn"),  # Bab-el-Mandeb
    ("Najd", "Persis"),  # Hormuz
    ("Lanka", "Dravida"),
    ("Malaya", "Sumatra"),
    ("Sumatra", "Java"),
    ("Java", "Borneo"),
    ("Borneo", "Luzon"),
    ("Luzon", "Formosa"),
    ("Formosa", "Lingnan"),
    ("Korea", "Yamato"),
    ("Yamato", "Ezo"),
    ("Ezo", "Amur"),  # Sakhalin
    ("Java", "Top End"),  # Timor Sea
    ("New Guinea", "Queensland"),  # Torres Strait
    ("Murray", "Aotearoa"),
    ("Madagascar", "Sofala"),
    ("Antilles", "Appalachia"),  # Florida Straits
    ("Antilles", "Yucatan"),
    ("Senegambia", "Sertao"),  # Dakar to Natal, the narrowest Atlantic crossing
]
WRAP_STRAITS = [("Chukotka", "Alaska")]  # Bering Strait, across the map edge

TERRAIN = {
    "grassland": "Plains", "steppe": "Plains", "savanna": "Plains", "desert": "Plains", "tundra": "Plains",
    "forest": "Forest", "taiga": "Forest", "jungle": "Forest",
    "hills": "Hills", "drylands": "Hills", "ice": "Hills",
    "mountains": "Mountain",
}


def build() -> Layout:
    land = land_mask()
    seeds = []
    for r in REGIONS:
        name, lat, lon, biome = r[:4]
        x, y = project(lon, lat)
        seeds.append(Seed(name, x, y, biome, nation=r[4] if len(r) > 4 else None))
    notes: list[str] = []
    labels, seeds = build_regions(land, seeds, notes)
    lay = Layout("earth", "Earth", "earth", W, H, labels, land, seeds, TERRAIN, notes=notes)
    finalize(lay)
    curated_straits(lay, STRAITS, WRAP_STRAITS)
    auto_connect(lay)
    assign_start_territories(lay)
    balance_start_development(lay)
    return lay


def background(lay: Layout) -> np.ndarray:
    from noise import mix, ramp, spectral
    from render import box_blur

    sea = ramp(
        0.6 * spectral((H, W), 11, beta=2.2, fmin=2, fmax=60) + 0.4 * spectral((H, W), 12, beta=1.2, fmin=40, stretch=(4, 1)),
        [(0, "#123a5c"), (0.5, "#1a4d74"), (1, "#25618c")],
    )
    near = np.clip(box_blur(lay.land.astype(np.float64), 6) * 2.2, 0, 1)
    sea = mix(sea, sea * 0.55 + np.array([0.18, 0.42, 0.5]) * 0.75, near * 0.8)
    # faint graticule every 30 degrees
    grid = np.zeros((H, W), dtype=bool)
    for lon in range(-150, 181, 30):
        x = int(round(project(lon, 0)[0])) % W
        grid[:, x] = True
    for lat in (-30, 0, 30, 60):
        y = int(round(project(0, lat)[1]))
        grid[y, :] = True
    return mix(sea, np.ones_like(sea), grid.astype(np.float64) * 0.12)
