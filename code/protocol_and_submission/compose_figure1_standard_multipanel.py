from __future__ import annotations

from pathlib import Path
import shutil

import pandas as pd
from PIL import Image, ImageDraw, ImageFont, ImageOps, JpegImagePlugin


ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "13_manuscript_and_submission" / "JNO_major_revision_package_20260524"
SUPP = PKG / "supplementary_figures"
MAIN = PKG / "main_figures"
OUTDIR = ROOT / "12_figures_tables_npj" / "standard_composites"

OUTDIR.mkdir(parents=True, exist_ok=True)

W = 4200
MARGIN_X = 170
MARGIN_Y = 160
GAP_X = 125
GAP_Y = 130
PANEL_W = (W - 2 * MARGIN_X - GAP_X) // 2
PANEL_H = 1480
H = 2 * MARGIN_Y + 3 * PANEL_H + 2 * GAP_Y

NAVY = (21, 78, 96)
TEXT = (32, 38, 46)
GRAY = (96, 106, 116)
LIGHT = (229, 236, 240)
PALE = (247, 250, 252)
BLUE = (31, 119, 180)
RED = (203, 75, 75)
TEAL = (0, 113, 128)
ORANGE = (230, 126, 34)
GREEN = (46, 160, 67)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    names = [
        "arialbd.ttf" if bold else "arial.ttf",
        "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf",
        "LiberationSans-Bold.ttf" if bold else "LiberationSans-Regular.ttf",
    ]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


FONT_LABEL = font(58, True)
FONT_TITLE = font(46, True)
FONT_SUB = font(29)
FONT_SMALL = font(25)
FONT_TINY = font(22)
FONT_AXIS = font(24)


def trim_white(img: Image.Image, threshold: int = 248, pad: int = 32) -> Image.Image:
    rgb = img.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    xs, ys = [], []
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if r < threshold or g < threshold or b < threshold:
                xs.append(x)
                ys.append(y)
    if not xs:
        return rgb
    left = max(0, min(xs) - pad)
    top = max(0, min(ys) - pad)
    right = min(w, max(xs) + pad)
    bottom = min(h, max(ys) + pad)
    return rgb.crop((left, top, right, bottom))


def place_image(canvas: Image.Image, img_path: Path, box: tuple[int, int, int, int], threshold: int = 248) -> None:
    x, y, w, h = box
    img = trim_white(Image.open(img_path), threshold=threshold, pad=36)
    img.thumbnail((w - 70, h - 90), Image.Resampling.LANCZOS)
    px = x + (w - img.width) // 2
    py = y + 58 + (h - 80 - img.height) // 2
    canvas.paste(img, (px, py))


def panel_box(col: int, row: int) -> tuple[int, int, int, int]:
    x = MARGIN_X + col * (PANEL_W + GAP_X)
    y = MARGIN_Y + row * (PANEL_H + GAP_Y)
    return x, y, PANEL_W, PANEL_H


def draw_panel_frame(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str) -> None:
    x, y, w, h = box
    draw.rounded_rectangle((x, y, x + w, y + h), radius=18, fill="white", outline=LIGHT, width=3)
    lx, ly = x + 24, y + 24
    draw.rounded_rectangle((lx, ly, lx + 70, ly + 58), radius=12, fill=(18, 31, 45))
    draw.text((lx + 22, ly + 7), label, fill="white", font=FONT_LABEL)


def rounded_text(draw, xy, text, fill, outline, txt_color, fnt, radius=20, pad_x=28, pad_y=14) -> tuple[int, int, int, int]:
    x, y = xy
    bbox = draw.textbbox((0, 0), text, font=fnt)
    w = bbox[2] - bbox[0] + 2 * pad_x
    h = bbox[3] - bbox[1] + 2 * pad_y
    draw.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=fill, outline=outline, width=2)
    draw.text((x + pad_x, y + pad_y - 2), text, fill=txt_color, font=fnt)
    return (x, y, x + w, y + h)


def draw_arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int], color=GRAY, width=5) -> None:
    draw.line((start, end), fill=color, width=width)
    ex, ey = end
    sx, sy = start
    dx = ex - sx
    dy = ey - sy
    if abs(dx) >= abs(dy):
        pts = [(ex, ey), (ex - 18 if dx > 0 else ex + 18, ey - 12), (ex - 18 if dx > 0 else ex + 18, ey + 12)]
    else:
        pts = [(ex, ey), (ex - 12, ey - 18 if dy > 0 else ey + 18), (ex + 12, ey - 18 if dy > 0 else ey + 18)]
    draw.polygon(pts, fill=color)


def draw_architecture(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x, y, w, h = box
    left = x + 125
    top = y + 120
    draw.text((left, top), "Analysis architecture", fill=TEXT, font=FONT_TITLE)
    draw.text((left, top + 56), "Primary hypothesis with secondary ecological layers", fill=GRAY, font=FONT_SUB)

    card_w = (w - 300) // 3
    card_h = 650
    cards = []
    titles = [("Diet exposure", RED), ("Microbiome layers", TEAL), ("Interpretation", ORANGE)]
    items = [
        ["E-DII primary", "DII secondary", "6 diet-quality indices"],
        ["Bray-Curtis primary", "alpha diversity", "CLR genera", "co-abundance modules"],
        ["FDR hierarchy", "direction consistency", "sensitivity checks", "exploratory paths"],
    ]
    for i in range(3):
        cx = x + 85 + i * (card_w + 65)
        cy = y + 265
        cards.append((cx, cy, card_w, card_h))
        draw.rounded_rectangle((cx, cy, cx + card_w, cy + card_h), radius=28, fill=PALE, outline=LIGHT, width=3)
        draw.ellipse((cx + card_w // 2 - 42, cy + 46, cx + card_w // 2 + 42, cy + 130), fill=titles[i][1])
        draw.text((cx + 34, cy + 160), titles[i][0], fill=TEXT, font=FONT_SUB)
        for j, item in enumerate(items[i]):
            rounded_text(draw, (cx + 36, cy + 230 + j * 88), item, "white", LIGHT, TEXT, FONT_TINY, radius=18, pad_x=18, pad_y=11)
    for i in range(2):
        x1, y1, ww, hh = cards[i]
        x2, y2, _, _ = cards[i + 1]
        draw_arrow(draw, (x1 + ww + 18, y1 + hh // 2), (x2 - 18, y2 + hh // 2), color=(130, 144, 156), width=5)

    fy = y + 1035
    draw.text((left, fy), "Evidence hierarchy", fill=TEXT, font=FONT_SUB)
    chips = [
        ("primary", RED),
        ("secondary", TEAL),
        ("suggestive", ORANGE),
        ("exploratory", GREEN),
    ]
    cx = left
    for text, color in chips:
        b = rounded_text(draw, (cx, fy + 64), text, (255, 255, 255), color, color, FONT_SMALL, radius=20, pad_x=28, pad_y=12)
        cx = b[2] + 24


def fmt_outcome(name: str) -> str:
    return {
        "observed_asv": "Observed ASVs",
        "faith_pd": "Faith's PD",
        "shannon_index": "Shannon",
        "inverse_simpson_index": "Inv. Simpson",
    }.get(name, name)


def draw_forest_axis(draw, origin, size, rows, title, xlim, color):
    ox, oy = origin
    aw, ah = size
    draw.text((ox, oy - 64), title, fill=TEXT, font=FONT_SUB)
    x0 = ox + 250
    x1 = ox + aw - 40
    y0 = oy + 30
    y1 = oy + ah - 95
    zero = x0 + (0 - xlim[0]) / (xlim[1] - xlim[0]) * (x1 - x0)
    draw.line((x0, y1, x1, y1), fill=(160, 170, 178), width=3)
    draw.line((zero, y0, zero, y1), fill=(160, 170, 178), width=3)
    ticks = [-2, 0, 2] if xlim[1] > 2 else [-1, 0, 1]
    for t in ticks:
        if xlim[0] <= t <= xlim[1]:
            tx = x0 + (t - xlim[0]) / (xlim[1] - xlim[0]) * (x1 - x0)
            draw.line((tx, y1 - 8, tx, y1 + 8), fill=GRAY, width=2)
            label = str(t)
            bb = draw.textbbox((0, 0), label, font=FONT_AXIS)
            draw.text((tx - (bb[2] - bb[0]) / 2, y1 + 20), label, fill=GRAY, font=FONT_AXIS)
    n = len(rows)
    for i, row in enumerate(rows):
        y = y0 + (i + 0.5) * (y1 - y0) / n
        draw.line((x0, y, x1, y), fill=(235, 240, 244), width=2)
        draw.text((ox + 12, y - 16), fmt_outcome(row["outcome"]), fill=TEXT, font=FONT_AXIS)
        lo = row["beta"] - 1.96 * row["se"]
        hi = row["beta"] + 1.96 * row["se"]
        bx = x0 + (row["beta"] - xlim[0]) / (xlim[1] - xlim[0]) * (x1 - x0)
        lx = x0 + (lo - xlim[0]) / (xlim[1] - xlim[0]) * (x1 - x0)
        hx = x0 + (hi - xlim[0]) / (xlim[1] - xlim[0]) * (x1 - x0)
        draw.line((max(x0, lx), y, min(x1, hx), y), fill=color, width=5)
        draw.ellipse((bx - 11, y - 11, bx + 11, y + 11), fill=color, outline="white", width=3)
    draw.text((x0 + 70, y1 + 58), "Beta per 1-SD higher PC score (95% CI)", fill=GRAY, font=FONT_TINY)


def draw_pca_alpha(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    draw = ImageDraw.Draw(canvas)
    x, y, w, h = box
    left = x + 130
    top = y + 120
    draw.text((left, top), "Diet PCA scores and alpha diversity", fill=TEXT, font=FONT_TITLE)
    draw.text((left, top + 56), "Survey-weighted model 3 estimates; all FDR values > 0.05", fill=GRAY, font=FONT_SUB)
    df = pd.read_excel(ROOT / "12_figures_tables_npj" / "three_tier_evidence_package" / "02_comparative_evidence" / "tables" / "CT04_npj_diet_PCA_patterns_results.xlsx", sheet_name="alpha_associations")
    order = ["observed_asv", "faith_pd", "shannon_index", "inverse_simpson_index"]
    pc1 = df[df["PC"].eq("PC1")].set_index("outcome").loc[order].reset_index().to_dict("records")
    pc2 = df[df["PC"].eq("PC2")].set_index("outcome").loc[order].reset_index().to_dict("records")
    draw_forest_axis(draw, (x + 90, y + 330), (w // 2 - 145, 780), pc1, "PC1 and alpha diversity", (-1.4, 1.4), BLUE)
    draw_forest_axis(draw, (x + w // 2 + 40, y + 330), (w // 2 - 130, 780), pc2, "PC2 and alpha diversity", (-4.0, 4.0), TEAL)


def compose() -> Path:
    canvas = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(canvas)
    panels = [
        ("A", panel_box(0, 0), SUPP / "Supplementary_Fig_S1_sample_flow.png"),
        ("B", panel_box(1, 0), SUPP / "Supplementary_Fig_S2_diet_correlation_network.png"),
        ("C", panel_box(0, 1), SUPP / "Supplementary_Fig_S3_diet_pca_loading.png"),
        ("D", panel_box(1, 1), None),
        ("E", panel_box(0, 2), None),
        ("F", panel_box(1, 2), SUPP / "Supplementary_Fig_S20_integrated_evidence.png"),
    ]
    for label, box, path in panels:
        draw_panel_frame(draw, box, label)
        if path is not None:
            place_image(canvas, path, box, threshold=250 if label in {"A", "B", "C"} else 252)
        elif label == "D":
            draw_architecture(canvas, box)
        elif label == "E":
            draw_pca_alpha(canvas, box)

    out_png = OUTDIR / "Figure_1_standard_multipanel.png"
    out_tif = OUTDIR / "Figure_1_standard_multipanel.tiff"
    out_pdf = OUTDIR / "Figure_1_standard_multipanel.pdf"
    canvas.save(out_png, dpi=(600, 600), quality=95)
    canvas.save(out_tif, dpi=(600, 600), compression="tiff_lzw")
    canvas.save(out_pdf, resolution=600.0)

    shutil.copy2(out_png, MAIN / "Figure_1_study_population_diet_architecture.png")
    shutil.copy2(out_png, MAIN / "Figure_1_standard_multipanel.png")
    return out_png


if __name__ == "__main__":
    result = compose()
    print(result)
