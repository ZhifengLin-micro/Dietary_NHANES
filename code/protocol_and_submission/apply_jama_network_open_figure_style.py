from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize
from matplotlib.lines import Line2D
from matplotlib.patches import Ellipse, Polygon
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "13_manuscript_and_submission" / "NPJ_Biofilms_submission_package_20260524"
SOURCE = PACKAGE / "Source_Data.xlsx"
MAIN_DIR = PACKAGE / "main_figures"
SUPP_DIR = PACKAGE / "supplementary_figures"
UPLOAD_DIR = PACKAGE / "figures_for_upload"
QA_DIR = PACKAGE / "qa_rendered_pages"

BLUE = "#1f77b4"
ORANGE = "#d95f02"
GREEN = "#2c7fb8"
RED = "#b2182b"
GRAY = "#5f6368"
LIGHT_GRAY = "#d9d9d9"
DARK = "#222222"
Q_COLORS = {"Q1": "#4c78a8", "Q2": "#72b7b2", "Q3": "#f2cf5b", "Q4": "#e45756"}
JAMA_CMAP = "RdBu_r"


def set_jama_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "Arial",
            "font.size": 8.5,
            "axes.titlesize": 9.5,
            "axes.labelsize": 8.5,
            "xtick.labelsize": 7.5,
            "ytick.labelsize": 7.5,
            "legend.fontsize": 7.5,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.edgecolor": "#333333",
            "axes.linewidth": 0.7,
            "axes.grid": False,
            "savefig.facecolor": "white",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def read(sheet: str) -> pd.DataFrame:
    return pd.read_excel(SOURCE, sheet_name=sheet)


def clean_axes(ax, keep_left: bool = True, keep_bottom: bool = True) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    if not keep_left:
        ax.spines["left"].set_visible(False)
        ax.tick_params(axis="y", length=0)
    if not keep_bottom:
        ax.spines["bottom"].set_visible(False)
        ax.tick_params(axis="x", length=0)
    ax.tick_params(colors=DARK, width=0.7)


def panel(ax, label: str) -> None:
    ax.text(
        -0.12,
        1.06,
        label,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=10,
        fontweight="bold",
        color=DARK,
    )


def save_figure(fig, main_name: str | None = None, supp_name: str | None = None, upload_num: int | None = None) -> None:
    targets: list[Path] = []
    if main_name:
        targets.append(MAIN_DIR / main_name)
    if supp_name:
        targets.append(SUPP_DIR / supp_name)
    if upload_num:
        targets.append(UPLOAD_DIR / f"Figure_{upload_num}.png")
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(target, dpi=300, bbox_inches="tight", pil_kwargs={"compress_level": 6})
        pdf_target = target.with_suffix(".pdf")
        fig.savefig(pdf_target, bbox_inches="tight")
        if target.parent == UPLOAD_DIR:
            im = Image.open(target).convert("RGB")
            im.save(target.with_suffix(".tiff"), compression="tiff_lzw", dpi=(300, 300))
    plt.close(fig)


def dot_matrix(
    ax,
    df: pd.DataFrame,
    x_col: str,
    y_col: str,
    color_col: str,
    size_col: str | None = None,
    x_order: list[str] | None = None,
    y_order: list[str] | None = None,
    cmap: str = JAMA_CMAP,
    center: float = 0,
    size_scale: float = 180,
    edge: bool = True,
    symmetric: bool = True,
) -> None:
    data = df.copy()
    if x_order is None:
        x_order = list(dict.fromkeys(data[x_col].astype(str)))
    if y_order is None:
        y_order = list(dict.fromkeys(data[y_col].astype(str)))
    x_map = {v: i for i, v in enumerate(x_order)}
    y_map = {v: i for i, v in enumerate(y_order)}
    data = data[data[x_col].astype(str).isin(x_map) & data[y_col].astype(str).isin(y_map)].copy()
    x = data[x_col].astype(str).map(x_map)
    y = data[y_col].astype(str).map(y_map)
    vals = pd.to_numeric(data[color_col], errors="coerce").fillna(0)
    if symmetric:
        max_abs = max(abs(vals.min() - center), abs(vals.max() - center), 1e-9)
        vmin, vmax = center - max_abs, center + max_abs
    else:
        vmin, vmax = float(vals.min()), float(vals.max())
        if vmin == vmax:
            vmax = vmin + 1e-9
    if size_col:
        raw = pd.to_numeric(data[size_col], errors="coerce").fillna(0)
        sizes = 25 + size_scale * (raw - raw.min()) / max(raw.max() - raw.min(), 1e-9)
    else:
        sizes = 70
    sc = ax.scatter(
        x,
        y,
        c=vals,
        s=sizes,
        cmap=cmap,
        vmin=vmin,
        vmax=vmax,
        edgecolors="#444444" if edge else "none",
        linewidths=0.35 if edge else 0,
    )
    ax.set_xticks(range(len(x_order)))
    ax.set_xticklabels(x_order, rotation=45, ha="right")
    ax.set_yticks(range(len(y_order)))
    ax.set_yticklabels(y_order)
    ax.set_xlim(-0.6, len(x_order) - 0.4)
    ax.set_ylim(-0.6, len(y_order) - 0.4)
    ax.invert_yaxis()
    clean_axes(ax)
    return sc


def heatmap(ax, mat: pd.DataFrame, cmap: str = JAMA_CMAP, center: float = 0, annotate: bool = False, fmt: str = ".2f"):
    vals = mat.astype(float).values
    max_abs = max(abs(np.nanmin(vals) - center), abs(np.nanmax(vals) - center), 1e-9)
    im = ax.imshow(vals, cmap=cmap, vmin=center - max_abs, vmax=center + max_abs, aspect="auto")
    ax.set_xticks(np.arange(mat.shape[1]))
    ax.set_xticklabels(mat.columns, rotation=45, ha="right")
    ax.set_yticks(np.arange(mat.shape[0]))
    ax.set_yticklabels(mat.index)
    if annotate and mat.shape[0] * mat.shape[1] <= 100:
        for i in range(mat.shape[0]):
            for j in range(mat.shape[1]):
                v = vals[i, j]
                if np.isfinite(v):
                    ax.text(j, i, format(v, fmt), ha="center", va="center", fontsize=6.5, color=DARK)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(length=0)
    return im


def sample_flow(ax) -> None:
    df = read("Fig1_sample_flow")
    df = df.iloc[::-1].reset_index(drop=True)
    y = np.arange(len(df))
    colors = [GRAY if i < 3 else BLUE for i in range(len(df))]
    colors[0] = RED
    colors[1] = "#008b8b"
    ax.barh(y, df["n"], color=colors, height=0.58)
    ax.set_yticks(y)
    ax.set_yticklabels(df["step"])
    ax.set_xlabel("Participants, No.")
    ax.set_xlim(0, df["n"].max() * 1.18)
    for yi, n in zip(y, df["n"]):
        ax.text(n + df["n"].max() * 0.025, yi, f"{int(n):,}", va="center", ha="left", fontsize=7.5)
    clean_axes(ax)


def diet_corr_heatmap(ax) -> None:
    df = read("Fig1_diet_spearman").rename(columns={"Unnamed: 0": "index"}).set_index("index")
    im = heatmap(ax, df, annotate=True, fmt=".2f")
    ax.set_xlabel("Diet index")
    ax.set_ylabel("Diet index")
    cb = plt.colorbar(im, ax=ax, fraction=0.044, pad=0.02)
    cb.set_label("Spearman r", fontsize=7.5)


def pca_loading(ax) -> None:
    df = read("Fig1_PCA_loadings")
    pcv = read("Fig1_PCA_variance")
    label_pos = {
        "HEI-2015": (0.445, 0.094, "left", "center"),
        "DASH": (0.445, 0.046, "left", "center"),
        "aMED": (0.445, -0.002, "left", "center"),
        "DII": (-0.315, 0.735, "center", "bottom"),
        "E-DII": (-0.405, 0.255, "right", "center"),
        "uPDI": (-0.385, 0.175, "right", "center"),
        "hPDI": (0.340, 0.565, "left", "center"),
        "PHDI": (0.382, 0.404, "left", "center"),
    }
    for _, row in df.iterrows():
        x, y = row["PC1"], row["PC2"]
        name = row["diet_index"]
        color = RED if row["diet_index"] in ["DII", "E-DII", "uPDI"] else BLUE
        ax.arrow(0, 0, x, y, color=color, alpha=0.75, linewidth=0.9, head_width=0.012, length_includes_head=True)
        tx, ty, ha, va = label_pos.get(name, (x * 1.08, y * 1.08, "center", "center"))
        if name in {"HEI-2015", "DASH", "aMED"}:
            ax.plot([x * 1.02, tx - 0.012], [y * 1.02, ty], color=LIGHT_GRAY, lw=0.45, zorder=1)
        ax.text(
            tx,
            ty,
            name,
            fontsize=7.2,
            ha=ha,
            va=va,
            bbox={"facecolor": "white", "edgecolor": "none", "alpha": 0.88, "pad": 0.7},
            zorder=3,
        )
    ax.axhline(0, color=LIGHT_GRAY, lw=0.7)
    ax.axvline(0, color=LIGHT_GRAY, lw=0.7)
    ax.set_xlim(-0.43, 0.58)
    ax.set_ylim(-0.055, 0.77)
    ax.set_xlabel(f"PC1 ({pcv.loc[0, 'variance_explained'] * 100:.1f}%)")
    ax.set_ylabel(f"PC2 ({pcv.loc[1, 'variance_explained'] * 100:.1f}%)")
    clean_axes(ax)


def evidence_scores(ax) -> None:
    df = read("Fig1_evidence_scores").sort_values("total_score")
    y = np.arange(len(df))
    ax.scatter(df["total_score"], y, s=65, color=BLUE, edgecolor=DARK, linewidth=0.35)
    ax.hlines(y, 0, df["total_score"], color=LIGHT_GRAY, lw=0.9)
    ax.set_yticks(y)
    ax.set_yticklabels(df["exposure_label"])
    ax.set_xlabel("Integrated descriptive score")
    ax.set_xlim(0, max(df["total_score"]) + 3)
    clean_axes(ax)


def figure1() -> None:
    fig, axes = plt.subplots(2, 2, figsize=(7.2, 5.6), constrained_layout=True)
    sample_flow(axes[0, 0])
    panel(axes[0, 0], "A")
    diet_corr_heatmap(axes[0, 1])
    panel(axes[0, 1], "B")
    pca_loading(axes[1, 0])
    panel(axes[1, 0], "C")
    evidence_scores(axes[1, 1])
    panel(axes[1, 1], "D")
    save_figure(fig, "Figure_1_study_population_diet_architecture.png", upload_num=1)
    # Preserve the short duplicate name used in the existing package.
    (MAIN_DIR / "Figure_1.png").write_bytes((MAIN_DIR / "Figure_1_study_population_diet_architecture.png").read_bytes())


def alpha_dot_panel(ax, compact: bool = True) -> None:
    df = read("Fig2_alpha_models")
    if compact:
        df = df[df["outcome_label"].isin(["Shannon index", "Observed ASVs"])].copy()
    df["label"] = df["exposure_label"] + " | " + df["outcome_label"]
    df = df.sort_values(["outcome_label", "beta_per_1sd"])
    y = np.arange(len(df))
    colors = np.where(df["p_fdr_global"] < 0.10, ORANGE, BLUE)
    for yi, (_, row), color in zip(y, df.iterrows(), colors):
        ax.errorbar(
            row["beta_per_1sd"],
            yi,
            xerr=[[row["beta_per_1sd"] - row["ci_low"]], [row["ci_high"] - row["beta_per_1sd"]]],
            fmt="o",
            color=BLUE,
            ecolor=LIGHT_GRAY,
            markerfacecolor="white",
            markeredgecolor=color,
            markersize=4.2,
            linewidth=0,
            elinewidth=0.8,
            capsize=2,
        )
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"])
    ax.set_xlabel("Beta per 1-SD higher diet index")
    clean_axes(ax)


def permanova_dot(ax, source_sheet: str = "Fig2_PERMANOVA", label_col: str = "r2") -> None:
    df = read(source_sheet)
    order_x = ["HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI"]
    metric_order = ["Bray-Curtis", "Jaccard", "Unweighted UniFrac", "Weighted UniFrac"]
    df["neglog"] = -np.log10(pd.to_numeric(df["p_fdr_global"], errors="coerce").clip(lower=1e-6))
    sc = dot_matrix(
        ax,
        df,
        "exposure_label",
        "beta_metric_label" if "beta_metric_label" in df.columns else "beta_metric",
        label_col,
        "neglog",
        x_order=order_x,
        y_order=metric_order,
        cmap="YlOrBr",
        center=0,
        size_scale=120,
        symmetric=False,
    )
    ax.set_xlabel("Diet index")
    ax.set_ylabel("Beta-diversity metric")
    cb = plt.colorbar(sc, ax=ax, fraction=0.05, pad=0.02)
    cb.set_label(label_col.replace("_", " "), fontsize=7.5)


def covariance_ellipse(points: np.ndarray, n_std: float = 1.65) -> tuple[float, float, float, float, float] | None:
    if points.shape[0] < 3:
        return None
    cov = np.cov(points, rowvar=False)
    if not np.all(np.isfinite(cov)):
        return None
    vals, vecs = np.linalg.eigh(cov)
    order = vals.argsort()[::-1]
    vals = vals[order]
    vecs = vecs[:, order]
    if vals[0] <= 0 or vals[1] <= 0:
        return None
    angle = math.degrees(math.atan2(vecs[1, 0], vecs[0, 0]))
    center = points.mean(axis=0)
    width, height = 2 * n_std * np.sqrt(vals)
    return center[0], center[1], width, height, angle


def convex_hull(points: np.ndarray) -> np.ndarray | None:
    pts = np.unique(points[np.isfinite(points).all(axis=1)], axis=0)
    if pts.shape[0] < 3:
        return None
    pts = pts[np.lexsort((pts[:, 1], pts[:, 0]))]

    def cross(o: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[np.ndarray] = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper: list[np.ndarray] = []
    for p in pts[::-1]:
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = np.array(lower[:-1] + upper[:-1])
    return hull if hull.shape[0] >= 3 else None


def pcoa_panel(ax, exposure: str = "E-DII", metric: str = "Bray-Curtis") -> None:
    df = read("SF_S7_PCoA_scores_sample")
    df = df[(df["exposure_label"] == exposure) & (df["beta_metric_label"] == metric)].copy()
    if df.empty:
        df = read("SF_S7_PCoA_scores_sample")
        df = df[df["beta_metric_label"] == metric].copy()
    if df.empty:
        df = read("SF_S7_PCoA_scores_sample").copy()
    exposure_title = str(df["exposure_label"].iloc[0]) if not df.empty else exposure
    metric_title = str(df["beta_metric_label"].iloc[0]) if not df.empty else metric
    legend_handles = []
    for q in ["Q1", "Q2", "Q3", "Q4"]:
        sub = df[df["quartile"] == q]
        if sub.empty:
            continue
        color = Q_COLORS.get(q, GRAY)
        pts = sub[["PCoA1", "PCoA2"]].to_numpy(float)
        hull = convex_hull(pts)
        if hull is not None:
            ax.add_patch(
                Polygon(
                    hull,
                    closed=True,
                    facecolor="none",
                    edgecolor=color,
                    linewidth=0.75,
                    linestyle=(0, (3, 2)),
                    alpha=0.75,
                    zorder=1,
                    clip_on=False,
                )
            )
        ellipse = covariance_ellipse(pts, n_std=1.65)
        if ellipse is not None:
            x, y, width, height, angle = ellipse
            ax.add_patch(
                Ellipse(
                    (x, y),
                    width,
                    height,
                    angle=angle,
                    facecolor=color,
                    edgecolor=color,
                    linewidth=1.0,
                    alpha=0.12,
                    zorder=2,
                )
            )
            ax.add_patch(
                Ellipse(
                    (x, y),
                    width,
                    height,
                    angle=angle,
                    facecolor="none",
                    edgecolor=color,
                    linewidth=1.0,
                    alpha=0.95,
                    zorder=3,
                )
            )
        ax.scatter(sub["PCoA1"], sub["PCoA2"], s=5.5, alpha=0.26, color=color, linewidths=0, zorder=4)
        legend_handles.append(
            Line2D([0], [0], marker="o", color="none", markerfacecolor=color, markeredgecolor=color, markersize=4.6, label=q)
        )
    pv = read("Fig2_PCoA_variance")
    row_match = pv[pv["beta_metric_label"] == metric_title]
    row = row_match.iloc[0] if not row_match.empty else pv.iloc[0]
    ax.set_xlabel(f"PCoA 1 ({row['axis1_variance_pct']:.1f}%)")
    ax.set_ylabel(f"PCoA 2 ({row['axis2_variance_pct']:.1f}%)")
    ax.legend(
        handles=legend_handles,
        title=exposure_title,
        frameon=False,
        ncol=4,
        loc="upper center",
        bbox_to_anchor=(0.5, -0.24),
        handletextpad=0.25,
        columnspacing=0.9,
        borderaxespad=0,
    )
    clean_axes(ax)


def permdisp_dot(ax) -> None:
    df = read("Fig2_PERMDISP")
    order_x = ["HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI"]
    metric_order = ["Bray-Curtis", "Jaccard", "Unweighted UniFrac", "Weighted UniFrac"]
    df["neglog"] = -np.log10(pd.to_numeric(df["p_fdr_global"], errors="coerce").clip(lower=1e-6))
    sc = dot_matrix(
        ax,
        df,
        "exposure_label",
        "beta_metric",
        "max_minus_min_mean_distance",
        "neglog",
        x_order=order_x,
        y_order=metric_order,
        cmap="YlOrBr",
        center=0,
        size_scale=120,
        symmetric=False,
    )
    ax.set_xlabel("Diet index")
    ax.set_ylabel("Beta-diversity metric")
    cb = plt.colorbar(sc, ax=ax, fraction=0.05, pad=0.02)
    cb.set_label("Max-min mean distance", fontsize=7.5)


def figure2() -> None:
    fig, axes = plt.subplots(2, 2, figsize=(7.3, 5.8), constrained_layout=True)
    alpha_dot_panel(axes[0, 0], compact=True)
    panel(axes[0, 0], "A")
    permanova_dot(axes[0, 1], "Fig2_PERMANOVA", "r2")
    panel(axes[0, 1], "B")
    pcoa_panel(axes[1, 0], "E-DII", "Bray-Curtis")
    panel(axes[1, 0], "C")
    permdisp_dot(axes[1, 1])
    panel(axes[1, 1], "D")
    save_figure(fig, "Figure_2_microbiome_diversity.png", upload_num=2)


def da_matrix(ax, top_n: int = 20) -> None:
    df = read("Fig3_DA_top_taxa")
    df = df.nsmallest(top_n, "p_value").copy()
    taxa_order = list(dict.fromkeys(df.sort_values("p_value")["tax_label"]))
    exp_order = ["HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI"]
    df["neglog"] = -np.log10(pd.to_numeric(df["p_value"], errors="coerce").clip(lower=1e-6))
    sc = dot_matrix(ax, df, "exposure_label", "tax_label", "beta_per_1sd", "neglog", exp_order, taxa_order, size_scale=120)
    ax.set_xlabel("Diet index")
    ax.set_ylabel("Taxon")
    cb = plt.colorbar(sc, ax=ax, fraction=0.04, pad=0.02)
    cb.set_label("CLR beta", fontsize=7.5)


def key_taxa_dose(ax, top_n: int = 20) -> None:
    df = read("Fig3_key_taxa_dose")
    df = df.nsmallest(top_n, "p_linear").copy()
    df["ci_low"] = df["beta_linear"] - 1.96 * df["se_linear"]
    df["ci_high"] = df["beta_linear"] + 1.96 * df["se_linear"]
    df["label"] = df["tax_label"] + " | " + df["exposure_label"]
    df = df.sort_values("beta_linear")
    y = np.arange(len(df))
    colors = np.where(df["beta_linear"] >= 0, RED, BLUE)
    for yi, (_, row), color in zip(y, df.iterrows(), colors):
        ax.errorbar(
            row["beta_linear"],
            yi,
            xerr=[[row["beta_linear"] - row["ci_low"]], [row["ci_high"] - row["beta_linear"]]],
            fmt="o",
            ecolor=LIGHT_GRAY,
            color=DARK,
            markerfacecolor=color,
            markeredgecolor=DARK,
            markersize=4,
            linewidth=0,
            elinewidth=0.8,
            capsize=2,
        )
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"])
    ax.set_xlabel("Linear beta per 1-SD higher diet index")
    clean_axes(ax)


def figure3() -> None:
    fig, axes = plt.subplots(1, 2, figsize=(7.4, 5.1), constrained_layout=True, gridspec_kw={"width_ratios": [1.1, 1]})
    da_matrix(axes[0], 22)
    panel(axes[0], "A")
    key_taxa_dose(axes[1], 20)
    panel(axes[1], "B")
    save_figure(fig, "Figure_3_recurrent_taxa_dose_response.png", upload_num=3)


def module_assoc(ax, top_n: int = 20) -> None:
    df = read("Fig4_module_assoc")
    df = df.nsmallest(top_n, "p_fdr_global").copy()
    df["label"] = df["module_id"] + " | " + df["exposure_label"]
    df = df.sort_values("beta_per_1sd")
    y = np.arange(len(df))
    colors = np.where(df["p_fdr_global"] < 0.10, ORANGE, BLUE)
    for yi, (_, row), color in zip(y, df.iterrows(), colors):
        ax.errorbar(
            row["beta_per_1sd"],
            yi,
            xerr=[[row["beta_per_1sd"] - row["ci_low"]], [row["ci_high"] - row["beta_per_1sd"]]],
            fmt="o",
            ecolor=LIGHT_GRAY,
            markerfacecolor="white",
            markeredgecolor=color,
            color=BLUE,
            markersize=4.2,
            linewidth=0,
            elinewidth=0.8,
            capsize=2,
        )
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"])
    ax.set_xlabel("Module-score beta per 1-SD higher diet index")
    clean_axes(ax)


def taxa_evidence_heatmap(ax, top_n: int = 18) -> None:
    df = read("SF_S10_taxa_evidence").nlargest(top_n, "multi_evidence_score").copy()
    cols = [
        "n_lefse_indices",
        "n_clr_nominal_indices",
        "n_clr_fdr_exposure_indices",
        "n_module_diet_nominal_indices",
        "n_module_diet_fdr_global_indices",
        "selected_degree",
    ]
    labels = ["LEfSe", "CLR nominal", "CLR FDR", "Module nominal", "Module FDR", "Network degree"]
    mat = df.set_index("tax_label")[cols]
    mat.columns = labels
    im = ax.imshow(mat.values, cmap="Blues", aspect="auto")
    ax.set_xticks(np.arange(len(labels)))
    ax.set_xticklabels(labels, rotation=45, ha="right")
    ax.set_yticks(np.arange(len(mat.index)))
    ax.set_yticklabels(mat.index)
    for i in range(mat.shape[0]):
        for j in range(mat.shape[1]):
            ax.text(j, i, f"{mat.values[i, j]:.0f}", ha="center", va="center", fontsize=6.3, color=DARK)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(length=0)
    cb = plt.colorbar(im, ax=ax, fraction=0.04, pad=0.02)
    cb.set_label("Count or degree", fontsize=7.5)


def figure4() -> None:
    fig, axes = plt.subplots(1, 2, figsize=(7.4, 5.3), constrained_layout=True, gridspec_kw={"width_ratios": [1, 1.05]})
    module_assoc(axes[0], 20)
    panel(axes[0], "A")
    taxa_evidence_heatmap(axes[1], 18)
    panel(axes[1], "B")
    save_figure(fig, "Figure_4_ecological_modules_evidence.png", upload_num=4)


def mediation_summary_plot(ax) -> None:
    df = read("Fig5_mediation_summary").sort_values("nominal_indirect")
    y = np.arange(len(df))
    ax.scatter(df["nominal_indirect"], y, s=55, color=BLUE, edgecolor=DARK, linewidth=0.35, label="Nominal")
    ax.scatter(df["fdr_outcome_10"], y + 0.15, s=35, color=ORANGE, edgecolor=DARK, linewidth=0.35, label="FDR by outcome")
    ax.set_yticks(y)
    ax.set_yticklabels(df["exposure_label"])
    ax.set_xlabel("Exploratory association-path summaries, No.")
    ax.legend(frameon=False, loc="lower right")
    clean_axes(ax)


def figure5() -> None:
    fig, ax = plt.subplots(figsize=(5.8, 3.4), constrained_layout=True)
    mediation_summary_plot(ax)
    save_figure(fig, "Figure_5_oral_health_path_summary.png")


def supplementary_figures() -> None:
    # S1-S3 mirror single core panels.
    fig, ax = plt.subplots(figsize=(5.2, 3.2), constrained_layout=True)
    sample_flow(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S1_sample_flow.png")

    fig, ax = plt.subplots(figsize=(4.8, 4.1), constrained_layout=True)
    diet_corr_heatmap(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S2_diet_correlation_network.png")

    fig, ax = plt.subplots(figsize=(4.6, 3.6), constrained_layout=True)
    pca_loading(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S3_diet_pca_loading.png")

    fig, ax = plt.subplots(figsize=(6.0, 6.0), constrained_layout=True)
    alpha_dot_panel(ax, compact=False)
    save_figure(fig, supp_name="Supplementary_Fig_S4_alpha_forest.png")

    rcs = read("Fig2_alpha_RCS_tests")
    rcs["overall_sig"] = -np.log10(pd.to_numeric(rcs["p_overall_fdr"], errors="coerce").clip(lower=1e-6))
    rcs["nonlinear_sig"] = -np.log10(pd.to_numeric(rcs["p_nonlinear_fdr"], errors="coerce").clip(lower=1e-6))
    rcs_long = rcs.melt(
        id_vars=["exposure_label", "outcome_label"],
        value_vars=["overall_sig", "nonlinear_sig"],
        var_name="test",
        value_name="neglog_fdr",
    )
    rcs_long["test"] = rcs_long["test"].map({"overall_sig": "Overall", "nonlinear_sig": "Nonlinear"})
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 4.8), constrained_layout=True)
    for ax, test in zip(axes, ["Overall", "Nonlinear"]):
        sub = rcs_long[rcs_long["test"] == test]
        sc = dot_matrix(
            ax,
            sub,
            "exposure_label",
            "outcome_label",
            "neglog_fdr",
            None,
            ["HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI"],
            ["Observed ASVs", "Faith's PD", "Shannon index", "Inverse Simpson index"],
            cmap="YlOrBr",
            center=0,
            size_scale=1,
            symmetric=False,
        )
        ax.set_xlabel("Diet index")
        ax.set_ylabel("")
        ax.set_title(test)
    save_figure(fig, supp_name="Supplementary_Fig_S5_alpha_rcs.png")

    fig, ax = plt.subplots(figsize=(6.0, 3.8), constrained_layout=True)
    permanova_dot(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S6_permanova_bubble_jaccard.png")

    fig, ax = plt.subplots(figsize=(5.8, 4.4), constrained_layout=True)
    pcoa_panel(ax, "HEI-2015", "Bray-Curtis")
    save_figure(fig, supp_name="Supplementary_Fig_S7_pcoa_quartiles.png")

    fig, ax = plt.subplots(figsize=(6.0, 3.8), constrained_layout=True)
    permdisp_dot(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S8_permdisp_dotmatrix.png")

    df = read("SF_S9_DA_validation").sort_values("n_nominal_both")
    fig, ax = plt.subplots(figsize=(4.8, 3.4), constrained_layout=True)
    y = np.arange(len(df))
    ax.scatter(df["n_nominal_both"], y, s=55, color=BLUE, edgecolor=DARK, linewidth=0.35, label="Nominal overlap")
    ax.scatter(df["n_fdr_any"], y + 0.15, s=45, color=ORANGE, edgecolor=DARK, linewidth=0.35, label="Any FDR")
    ax.set_yticks(y)
    ax.set_yticklabels(df["exposure_label"])
    ax.set_xlabel("Taxa, No.")
    ax.legend(frameon=False, loc="lower right")
    clean_axes(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S9_da_validation.png")

    fig, ax = plt.subplots(figsize=(5.8, 5.2), constrained_layout=True)
    taxa_evidence_heatmap(ax, 22)
    save_figure(fig, supp_name="Supplementary_Fig_S10_taxa_scorecard.png")

    df = read("SF_S10_taxa_evidence").nlargest(25, "multi_evidence_score").sort_values("multi_evidence_score")
    fig, ax = plt.subplots(figsize=(5.6, 5.0), constrained_layout=True)
    y = np.arange(len(df))
    ax.scatter(df["multi_evidence_score"], y, s=35 + df["selected_degree"] * 4, color=BLUE, alpha=0.85, edgecolor=DARK, linewidth=0.3)
    ax.set_yticks(y)
    ax.set_yticklabels(df["tax_label"])
    ax.set_xlabel("Exploratory evidence score")
    clean_axes(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S11_circular_taxa.png")

    upset_plot()

    fig, ax = plt.subplots(figsize=(5.9, 5.1), constrained_layout=True)
    key_taxa_dose(ax, 24)
    save_figure(fig, supp_name="Supplementary_Fig_S13_key_taxa_dose_response.png")

    network_plot()

    fig, ax = plt.subplots(figsize=(5.8, 4.4), constrained_layout=True)
    bridge_plot(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S15_module_bridge.png")

    community_type_heatmap()

    subgroup_plot()

    med_dental_plot()

    weighted_unweighted_plot()

    fig, ax = plt.subplots(figsize=(6.2, 5.8), constrained_layout=True)
    taxa_evidence_heatmap(ax, 30)
    save_figure(fig, supp_name="Supplementary_Fig_S20_integrated_evidence.png")

    fig, ax = plt.subplots(figsize=(4.8, 3.4), constrained_layout=True)
    mediation_summary_plot(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S21_path_coefficients.png")


def upset_plot() -> None:
    df = read("SF_S12_upset").head(11).copy()
    cols = ["LEfSe", "CLR nominal", "CLR FDR", "Diet-associated module", "Network hub"]
    fig = plt.figure(figsize=(6.2, 4.6), constrained_layout=True)
    gs = fig.add_gridspec(2, 1, height_ratios=[1, 1.35])
    ax_bar = fig.add_subplot(gs[0])
    ax_mat = fig.add_subplot(gs[1], sharex=ax_bar)
    x = np.arange(len(df))
    ax_bar.vlines(x, 0, df["intersection_size"], color=BLUE, lw=2.6)
    ax_bar.scatter(x, df["intersection_size"], color=BLUE, s=28)
    ax_bar.set_ylabel("Taxa, No.")
    ax_bar.set_xticks([])
    clean_axes(ax_bar, keep_bottom=False)
    for j, col in enumerate(cols):
        vals = df[col].astype(bool).values
        ax_mat.scatter(x[vals], np.full(vals.sum(), j), color=BLUE, s=28)
        ax_mat.scatter(x[~vals], np.full((~vals).sum(), j), facecolor="white", edgecolor=LIGHT_GRAY, s=24)
    ax_mat.set_yticks(np.arange(len(cols)))
    ax_mat.set_yticklabels(cols)
    ax_mat.set_xlabel("Intersection")
    ax_mat.set_ylim(-0.7, len(cols) - 0.3)
    clean_axes(ax_mat)
    save_figure(fig, supp_name="Supplementary_Fig_S12_upset_taxa.png")


def bridge_plot(ax) -> None:
    df = read("Fig4_bridge").nsmallest(24, "p_fdr_global_diet").copy()
    df["label"] = df["module_id"] + " | " + df["exposure_label"] + " | " + df["outcome"]
    df = df.sort_values("beta_diet")
    y = np.arange(len(df))
    colors = np.where(df["bridge_direction"].eq("same_direction"), RED, BLUE)
    ax.scatter(df["beta_diet"], y, s=45, color=colors, edgecolor=DARK, linewidth=0.3)
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"])
    ax.set_xlabel("Diet-module beta")
    clean_axes(ax)


def network_plot() -> None:
    import networkx as nx

    df = read("SF_S10_taxa_evidence").nlargest(35, "selected_degree").copy()
    modules = sorted(df["module_id"].dropna().unique())
    g = nx.Graph()
    for m in modules:
        g.add_node(m, kind="module")
    for _, row in df.iterrows():
        tax = str(row["tax_label"])
        mod = str(row["module_id"])
        g.add_node(tax, kind="taxon", score=float(row["multi_evidence_score"]), degree=float(row["selected_degree"]))
        g.add_edge(mod, tax, weight=max(float(row["selected_degree"]), 1.0))
    pos = nx.spring_layout(g, seed=6, k=0.9)
    fig, ax = plt.subplots(figsize=(6.6, 5.3), constrained_layout=True)
    nx.draw_networkx_edges(g, pos, ax=ax, width=0.6, edge_color="#bdbdbd", alpha=0.7)
    tax_nodes = [n for n, d in g.nodes(data=True) if d.get("kind") == "taxon"]
    mod_nodes = [n for n, d in g.nodes(data=True) if d.get("kind") == "module"]
    sizes = [35 + 5 * g.nodes[n].get("degree", 1) for n in tax_nodes]
    nx.draw_networkx_nodes(g, pos, nodelist=tax_nodes, node_color=BLUE, node_size=sizes, alpha=0.82, edgecolors=DARK, linewidths=0.25, ax=ax)
    nx.draw_networkx_nodes(g, pos, nodelist=mod_nodes, node_color=ORANGE, node_size=180, alpha=0.9, edgecolors=DARK, linewidths=0.35, ax=ax)
    labels = {n: n for n in mod_nodes}
    top_tax = df.nlargest(8, "multi_evidence_score")["tax_label"].astype(str).tolist()
    labels.update({n: n for n in top_tax if n in g})
    nx.draw_networkx_labels(g, pos, labels=labels, font_size=7, font_family="Arial", ax=ax)
    ax.set_axis_off()
    save_figure(fig, supp_name="Supplementary_Fig_S14_ecological_network.png")


def community_type_heatmap() -> None:
    df = read("SF_S16_comm_types")
    top_taxa = df.groupby("tax_label")["mean_relative_abundance"].sum().sort_values(ascending=False).head(18).index
    mat = df[df["tax_label"].isin(top_taxa)].pivot_table(
        index="tax_label", columns="community_type", values="mean_relative_abundance", aggfunc="sum"
    ).fillna(0)
    mat = mat.loc[mat.sum(axis=1).sort_values(ascending=True).index]
    fig, ax = plt.subplots(figsize=(4.8, 5.2), constrained_layout=True)
    im = ax.imshow(mat.values * 100, cmap="Blues", aspect="auto")
    ax.set_xticks(np.arange(mat.shape[1]))
    ax.set_xticklabels(mat.columns)
    ax.set_yticks(np.arange(mat.shape[0]))
    ax.set_yticklabels(mat.index)
    for i in range(mat.shape[0]):
        for j in range(mat.shape[1]):
            v = mat.values[i, j] * 100
            if v >= 1:
                ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=6.2, color=DARK)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(length=0)
    cb = plt.colorbar(im, ax=ax, fraction=0.05, pad=0.02)
    cb.set_label("Mean relative abundance, %", fontsize=7.5)
    save_figure(fig, supp_name="Supplementary_Fig_S16_community_type.png")


def subgroup_plot() -> None:
    df = read("SF_S17_strata_estimates")
    df = df.dropna(subset=["beta_per_1sd", "ci_low", "ci_high", "p_value"]).nsmallest(24, "p_value").copy()
    df["label"] = df["domain"] + " | " + df["exposure_label"] + " | " + df["modifier_label"] + ": " + df["subgroup_level"].astype(str)
    df = df.sort_values("beta_per_1sd")
    y = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(6.2, 5.4), constrained_layout=True)
    colors = np.where(df["beta_per_1sd"] >= 0, RED, BLUE)
    for yi, (_, row), color in zip(y, df.iterrows(), colors):
        ax.errorbar(
            row["beta_per_1sd"],
            yi,
            xerr=[[row["beta_per_1sd"] - row["ci_low"]], [row["ci_high"] - row["beta_per_1sd"]]],
            fmt="o",
            ecolor=LIGHT_GRAY,
            markerfacecolor=color,
            markeredgecolor=DARK,
            markersize=3.5,
            linewidth=0,
            elinewidth=0.75,
            capsize=1.8,
        )
    ax.axvline(0, color="#888888", lw=0.8)
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"])
    ax.set_xlabel("Stratum-specific beta per 1-SD diet index")
    clean_axes(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S17_subgroup_interaction.png")


def med_dental_plot() -> None:
    df = read("Fig5_med_dental_sens")
    df["rate"] = 100 * df["n_direction_consistent"] / df["n_models"]
    df = df.sort_values("rate")
    y = np.arange(len(df))
    fig, ax = plt.subplots(figsize=(5.2, 3.5), constrained_layout=True)
    ax.scatter(df["rate"], y, s=55, color=BLUE, edgecolor=DARK, linewidth=0.35)
    ax.hlines(y, 0, df["rate"], color=LIGHT_GRAY, lw=1)
    ax.set_yticks(y)
    ax.set_yticklabels(df["scenario"].str.replace("_", " "))
    ax.set_xlabel("Direction-consistent models, %")
    ax.set_xlim(0, 105)
    clean_axes(ax)
    save_figure(fig, supp_name="Supplementary_Fig_S18_med_dental_sensitivity.png")


def weighted_unweighted_plot() -> None:
    df = read("Fig5_weight_compare")
    df["rate"] = 100 * df["n_direction_consistent"] / df["n_models"]
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 3.3), constrained_layout=True)
    y = np.arange(len(df))
    axes[0].scatter(df["rate"], y, s=50, color=BLUE, edgecolor=DARK, linewidth=0.3)
    axes[0].set_yticks(y)
    axes[0].set_yticklabels(df["analysis_family"].str.replace("_", " "))
    axes[0].set_xlabel("Direction-consistent models, %")
    axes[0].set_xlim(0, 105)
    clean_axes(axes[0])
    axes[1].scatter(df["median_abs_delta"], y, s=50, color=ORANGE, edgecolor=DARK, linewidth=0.3)
    axes[1].set_yticks(y)
    axes[1].set_yticklabels([])
    axes[1].set_xlabel("Median absolute beta delta")
    clean_axes(axes[1])
    panel(axes[0], "A")
    panel(axes[1], "B")
    save_figure(fig, supp_name="Supplementary_Fig_S19_weighted_unweighted.png")


def rebuild_documents() -> None:
    sys.path.insert(0, str(ROOT / "00_protocol_and_log"))
    import build_npj_biofilms_submission_package as npj

    # Do not call npj.main() or prepare_support_files(); those would restore the older npj/yuting style figures.
    npj.base.SRC = PACKAGE
    npj.base.TABLES = PACKAGE / "Supplementary_Data_1_numeric_tables.xlsx"
    npj.base.SOURCE_DATA = PACKAGE / "Source_Data.xlsx"
    npj.base.DST = PACKAGE
    npj.base.FINAL_DST = PACKAGE
    npj.build_main()
    npj.build_supplement()


def contact_sheet() -> None:
    imgs = list(MAIN_DIR.glob("*.png")) + list(SUPP_DIR.glob("*.png"))
    cols = 3
    thumb_w, thumb_h = 420, 300
    rows = math.ceil(len(imgs) / cols)
    sheet = Image.new("RGB", (cols * thumb_w, rows * thumb_h), "white")
    from PIL import ImageDraw, ImageFont

    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        font = None
    for i, path in enumerate(imgs):
        im = Image.open(path).convert("RGB")
        im.thumbnail((thumb_w - 24, thumb_h - 46), Image.LANCZOS)
        x = (i % cols) * thumb_w + 12
        y = (i // cols) * thumb_h + 34
        sheet.paste(im, (x, y))
        draw.text((x, y - 24), path.name[:54], fill=(0, 0, 0), font=font)
    QA_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(QA_DIR / "figure_contact_sheet_jama_style.png", dpi=(150, 150))


def main() -> None:
    set_jama_style()
    MAIN_DIR.mkdir(parents=True, exist_ok=True)
    SUPP_DIR.mkdir(parents=True, exist_ok=True)
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    QA_DIR.mkdir(parents=True, exist_ok=True)
    figure1()
    figure2()
    figure3()
    figure4()
    figure5()
    supplementary_figures()
    rebuild_documents()
    contact_sheet()
    notes = PACKAGE / "JAMA_Network_Open_figure_style_notes.md"
    notes.write_text(
        "# JAMA Network Open figure-style update\n\n"
        "- Rebuilt main and supplementary figures from Source_Data.xlsx using a restrained JAMA-like statistical style.\n"
        "- Used Arial-compatible typography, white backgrounds, labeled axes, defined colors, and limited main figures to no more than 4 panels.\n"
        "- Replaced stacked composition and ribbon-style summaries with dot plots or heatmaps where possible.\n"
        "- Updated manuscript and supplementary Word files so embedded figures match the regenerated image files.\n",
        encoding="utf-8",
    )
    print(PACKAGE)


if __name__ == "__main__":
    main()
