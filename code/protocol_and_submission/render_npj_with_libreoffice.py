from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

import fitz
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
PKG = ROOT / "13_manuscript_and_submission" / "NPJ_Biofilms_submission_package_20260524"
SOFFICE = Path(r"C:\Program Files\LibreOffice\program\soffice.exe")
QA = PKG / "qa_rendered_pages"
TMP = QA / "_tmp_ascii"
PDF_DIR = PKG / "pdf"


def render_pdf(pdf_path: Path, out_dir: Path, max_width: int = 1600) -> int:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    pdf = fitz.open(str(pdf_path))
    for index, page in enumerate(pdf, 1):
        zoom = max_width / page.rect.width
        pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
        pix.save(str(out_dir / f"page_{index:03d}.png"))
    count = len(pdf)
    pdf.close()
    return count


def make_contact_sheet(page_dir: Path, out_path: Path, cols: int = 3) -> None:
    pages = sorted(page_dir.glob("page_*.png"))
    if not pages:
        return
    thumb_w = 520
    label_h = 36
    gap = 24
    rows = (len(pages) + cols - 1) // cols
    thumb_h = 720
    sheet = Image.new("RGB", (cols * thumb_w + (cols + 1) * gap,
                              rows * (thumb_h + label_h) + (rows + 1) * gap), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    for idx, path in enumerate(pages):
        row, col = divmod(idx, cols)
        x = gap + col * (thumb_w + gap)
        y = gap + row * (thumb_h + label_h + gap)
        draw.text((x, y), path.name, fill="black", font=font)
        with Image.open(path) as im:
            im = im.convert("RGB")
            im.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            sheet.paste(im, (x, y + label_h))
    sheet.save(out_path, dpi=(150, 150))


def convert_docx(docx_path: Path, idx: int) -> Path:
    TMP.mkdir(parents=True, exist_ok=True)
    ascii_docx = TMP / f"npj_doc_{idx:02d}.docx"
    ascii_pdf = TMP / f"npj_doc_{idx:02d}.pdf"
    if ascii_pdf.exists():
        ascii_pdf.unlink()
    shutil.copy2(docx_path, ascii_docx)
    profile = TMP / f"lo_profile_{idx:02d}"
    profile.mkdir(exist_ok=True)
    cmd = [
        str(SOFFICE),
        f"-env:UserInstallation=file:///{profile.as_posix()}",
        "--headless",
        "--invisible",
        "--norestore",
        "--convert-to",
        "pdf",
        "--outdir",
        str(TMP),
        str(ascii_docx),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if not ascii_pdf.exists():
        raise FileNotFoundError(f"LibreOffice did not create {ascii_pdf}")
    named_pdf = PDF_DIR / f"{docx_path.stem}.pdf"
    shutil.copy2(ascii_pdf, named_pdf)
    return ascii_pdf


def main() -> None:
    if not SOFFICE.exists():
        raise FileNotFoundError(SOFFICE)
    PDF_DIR.mkdir(exist_ok=True)
    QA.mkdir(exist_ok=True)
    docs = [
        PKG / "Cover_letter_npj_Biofilms_and_Microbiomes.docx",
        PKG / "Manuscript_Dietary_inflammatory_potential_oral_microbiome_npj.docx",
        PKG / "Supplementary_Information_Diet_oral_microbiome_npj.docx",
    ]
    for idx, docx in enumerate(docs, 1):
        ascii_pdf = convert_docx(docx, idx)
        out_dir = QA / docx.stem
        pages = render_pdf(ascii_pdf, out_dir)
        make_contact_sheet(out_dir, QA / f"{docx.stem}_contact_sheet_new.png")
        print(f"{docx.name}: {pages} pages")


if __name__ == "__main__":
    main()
