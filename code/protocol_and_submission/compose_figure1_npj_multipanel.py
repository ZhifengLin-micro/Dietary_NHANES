from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, JpegImagePlugin

import compose_figure1_standard_multipanel as std


ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "13_manuscript_and_submission" / "NPJ_Biofilms_submission_package_20260524"
SUPP = PKG / "supplementary_figures"
MAIN = PKG / "main_figures"
UPLOAD = PKG / "figures_for_upload"
OUTDIR = ROOT / "12_figures_tables_npj" / "standard_composites"


def draw_npj_panel_frame(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str) -> None:
    x, y, w, h = box
    draw.rounded_rectangle((x, y, x + w, y + h), radius=18, fill="white", outline=std.LIGHT, width=3)
    lx, ly = x + 24, y + 24
    draw.rounded_rectangle((lx, ly, lx + 96, ly + 58), radius=12, fill=(18, 31, 45))
    draw.text((lx + 18, ly + 7), label, fill="white", font=std.FONT_LABEL)


def compose() -> Path:
    MAIN.mkdir(parents=True, exist_ok=True)
    UPLOAD.mkdir(parents=True, exist_ok=True)
    OUTDIR.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGB", (std.W, std.H), "white")
    draw = ImageDraw.Draw(canvas)
    panels = [
        ("a)", std.panel_box(0, 0), SUPP / "Supplementary_Fig_S1_sample_flow.png"),
        ("b)", std.panel_box(1, 0), SUPP / "Supplementary_Fig_S2_diet_correlation_network.png"),
        ("c)", std.panel_box(0, 1), SUPP / "Supplementary_Fig_S3_diet_pca_loading.png"),
        ("d)", std.panel_box(1, 1), None),
        ("e)", std.panel_box(0, 2), None),
        ("f)", std.panel_box(1, 2), SUPP / "Supplementary_Fig_S20_integrated_evidence.png"),
    ]
    for label, box, path in panels:
        draw_npj_panel_frame(draw, box, label)
        if path is not None:
            threshold = 250 if label in {"a)", "b)", "c)"} else 252
            std.place_image(canvas, path, box, threshold=threshold)
        elif label == "d)":
            std.draw_architecture(canvas, box)
        elif label == "e)":
            std.draw_pca_alpha(canvas, box)

    out_png = OUTDIR / "Figure_1_npj_multipanel.png"
    out_tif = OUTDIR / "Figure_1_npj_multipanel.tiff"
    out_pdf = OUTDIR / "Figure_1_npj_multipanel.pdf"
    canvas.save(out_png, dpi=(600, 600), quality=95)
    canvas.save(out_tif, dpi=(600, 600), compression="tiff_lzw")
    canvas.save(out_pdf, resolution=600.0)

    for dst in (
        MAIN / "Figure_1_study_population_diet_architecture.png",
        MAIN / "Figure_1.png",
        UPLOAD / "Figure_1.png",
    ):
        canvas.save(dst, dpi=(600, 600), quality=95)
    canvas.save(UPLOAD / "Figure_1.tiff", dpi=(600, 600), compression="tiff_lzw")
    return out_png


if __name__ == "__main__":
    print(compose())
