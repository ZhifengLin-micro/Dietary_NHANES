from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from textwrap import wrap

import matplotlib as mpl
import matplotlib.pyplot as plt
import networkx as nx
import numpy as np
import pandas as pd
import seaborn as sns
from matplotlib.colors import LinearSegmentedColormap, Normalize, TwoSlopeNorm
from matplotlib.lines import Line2D
from matplotlib.patches import PathPatch, Polygon
from matplotlib.path import Path as MplPath
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "12_figures_tables_npj" / "yuting_style_visualizations"
OUT_DIR.mkdir(parents=True, exist_ok=True)

EXPOSURE_ORDER = ["HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI"]
QUARTILE_ORDER = ["Q1", "Q2", "Q3", "Q4"]

PALETTE = {
    "navy": "#1F2937",
    "slate": "#4B5563",
    "grid": "#E5E7EB",
    "light": "#F8FAFC",
    "blue": "#2A6F97",
    "cyan": "#74A9CF",
    "gold": "#F6C85F",
    "orange": "#F4A261",
    "red": "#B2182B",
    "green": "#4C9F70",
    "purple": "#756BB1",
}

DIV_CMAP = LinearSegmentedColormap.from_list(
    "npj_diverging",
    ["#3B4CC0", "#9BC9DB", "#F7F7F7", "#F4A261", "#B2182B"],
)
SCORE_CMAP = LinearSegmentedColormap.from_list(
    "evidence_score",
    ["#F1F5F9", "#BBD7E7", "#5B9BBF", "#F4A261", "#B2182B"],
)

mpl.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "axes.edgecolor": PALETTE["navy"],
        "axes.labelcolor": PALETTE["navy"],
        "xtick.color": PALETTE["navy"],
        "ytick.color": PALETTE["navy"],
        "figure.facecolor": "white",
        "axes.facecolor": "white",
    }
)


manifest: list[dict[str, str]] = []


def read_csv(rel_path: str) -> pd.DataFrame:
    return pd.read_csv(ROOT / rel_path)


def bool_series(values: pd.Series) -> pd.Series:
    if pd.api.types.is_bool_dtype(values):
        return values.fillna(False)
    return values.astype(str).str.upper().isin(["TRUE", "T", "YES", "Y", "1"])


def finite_or(series: pd.Series, fallback: float) -> pd.Series:
    out = pd.to_numeric(series, errors="coerce")
    return out.replace([np.inf, -np.inf], np.nan).fillna(fallback)


def wrap_label(text: str, width: int = 18) -> str:
    return "\n".join(wrap(str(text), width=width, break_long_words=False)) or str(text)


def ellipsize_label(text: str, width: int = 24) -> str:
    label = str(text)
    return label if len(label) <= width else f"{label[: max(width - 3, 1)]}..."


def export_figure(fig: plt.Figure, stem: str, source_style: str, data_source: str, note: str) -> None:
    png_path = OUT_DIR / f"{stem}.png"
    pdf_path = OUT_DIR / f"{stem}.pdf"
    fig.savefig(png_path, dpi=300, bbox_inches="tight")
    fig.savefig(pdf_path, bbox_inches="tight")
    plt.close(fig)
    manifest.append(
        {
            "figure": stem,
            "png": str(png_path.relative_to(ROOT)),
            "pdf": str(pdf_path.relative_to(ROOT)),
            "source_style": source_style,
            "data_source": data_source,
            "note": note,
        }
    )


def add_panel_title(ax: plt.Axes, title: str, subtitle: str | None = None) -> None:
    ax.text(
        0,
        1.085,
        title,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=12.5,
        fontweight="bold",
        color=PALETTE["navy"],
    )
    if subtitle:
        ax.text(
            0,
            1.04,
            subtitle,
            transform=ax.transAxes,
            ha="left",
            va="bottom",
            fontsize=8.6,
            color=PALETTE["slate"],
        )


def figure_da_balloon() -> None:
    data_source = "15_da_validation_ANCOMBC2_MaAsLin3/processed/npj_da_validation_cross_method_consistency.csv"
    df = read_csv(data_source)
    for col in ["p_value_continuous", "p_value_q4", "beta_continuous"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df["p_min"] = df[["p_value_continuous", "p_value_q4"]].min(axis=1)
    df["nominal_both"] = bool_series(df["validated_nominal_both"])
    df["abs_beta"] = df["beta_continuous"].abs()

    ranked = (
        df.assign(rank_p=df["p_min"].fillna(1.0))
        .sort_values(["nominal_both", "rank_p", "abs_beta"], ascending=[False, True, False])
        .drop_duplicates("tax_label")
    )
    taxa_order = ranked["tax_label"].head(26).tolist()
    taxa_order = list(reversed(taxa_order))

    plot_df = (
        df[df["tax_label"].isin(taxa_order)]
        .groupby(["tax_label", "exposure_label"], as_index=False)
        .agg(
            beta=("beta_continuous", "mean"),
            p_min=("p_min", "min"),
            nominal_layers=("nominal_both", "sum"),
            n_rows=("feature_id", "count"),
        )
    )
    plot_df = plot_df[plot_df["exposure_label"].isin(EXPOSURE_ORDER)].copy()
    plot_df["x"] = plot_df["exposure_label"].map({v: i for i, v in enumerate(EXPOSURE_ORDER)})
    plot_df["y"] = plot_df["tax_label"].map({v: i for i, v in enumerate(taxa_order)})
    plot_df["strength"] = -np.log10(plot_df["p_min"].clip(lower=1e-12))
    plot_df["size"] = 35 + np.clip(plot_df["strength"], 0, 6) * 55

    beta_max = np.nanmax(np.abs(plot_df["beta"].to_numpy()))
    beta_max = 0.2 if not np.isfinite(beta_max) or beta_max == 0 else beta_max
    norm = TwoSlopeNorm(vmin=-beta_max, vcenter=0, vmax=beta_max)

    fig, ax = plt.subplots(figsize=(9.8, 9.4))
    ax.set_axisbelow(True)
    ax.grid(which="major", color=PALETTE["grid"], linewidth=0.85)
    sc = ax.scatter(
        plot_df["x"],
        plot_df["y"],
        s=plot_df["size"],
        c=plot_df["beta"],
        cmap=DIV_CMAP,
        norm=norm,
        edgecolor="#222222",
        linewidth=0.45,
        alpha=0.94,
    )
    for _, row in plot_df.iterrows():
        if row["nominal_layers"] > 0:
            ax.text(
                row["x"],
                row["y"],
                str(int(row["nominal_layers"])),
                ha="center",
                va="center",
                fontsize=6,
                color="#111827",
            )

    ax.set_xticks(range(len(EXPOSURE_ORDER)))
    ax.set_xticklabels(EXPOSURE_ORDER, rotation=35, ha="right")
    ax.set_yticks(range(len(taxa_order)))
    ax.set_yticklabels(taxa_order, fontsize=8)
    ax.set_xlim(-0.55, len(EXPOSURE_ORDER) - 0.45)
    ax.set_ylim(-0.6, len(taxa_order) - 0.4)
    ax.set_xlabel("Diet index")
    ax.set_ylabel("Validated or prioritized genus")
    add_panel_title(
        ax,
        "Cross-method differential abundance matrix",
        "Color shows continuous-model beta; bubble size shows the strongest continuous or Q4-vs-Q1 evidence.",
    )
    cbar = fig.colorbar(sc, ax=ax, fraction=0.035, pad=0.02)
    cbar.set_label("Mean CLR beta", fontsize=9)
    for pval, label in [(0.05, "P=0.05"), (0.01, "P=0.01"), (0.001, "P=0.001")]:
        ax.scatter([], [], s=35 + min(-np.log10(pval), 6) * 55, facecolor="white", edgecolor=PALETTE["navy"], label=label)
    ax.legend(title="Evidence size", frameon=False, loc="lower right", fontsize=8, title_fontsize=9)
    export_figure(
        fig,
        "Y01_da_validation_balloonplot",
        "Yuting ggballoonplot template",
        data_source,
        "Adapted balloon-heatmap logic to show diet-by-taxon CLR validation evidence.",
    )


def figure_community_stacked_bar() -> None:
    data_source = "16_community_typing/processed/npj_community_type_top_taxa.csv"
    df = read_csv(data_source)
    df["mean_relative_abundance"] = pd.to_numeric(df["mean_relative_abundance"], errors="coerce").fillna(0)
    top_taxa = (
        df.groupby("tax_label")["mean_relative_abundance"]
        .sum()
        .sort_values(ascending=False)
        .head(12)
        .index.tolist()
    )
    df["tax_plot"] = np.where(df["tax_label"].isin(top_taxa), df["tax_label"], "Other selected taxa")
    comp = df.groupby(["community_type", "tax_plot"], as_index=False)["mean_relative_abundance"].sum()
    pivot = comp.pivot(index="community_type", columns="tax_plot", values="mean_relative_abundance").fillna(0)
    col_order = [t for t in top_taxa if t in pivot.columns] + (["Other selected taxa"] if "Other selected taxa" in pivot.columns else [])
    pivot = pivot[col_order]
    pivot = pivot.div(pivot.sum(axis=1).replace(0, np.nan), axis=0).fillna(0)
    pivot = pivot.sort_index()

    colors = sns.color_palette("tab20", n_colors=len(pivot.columns))
    color_map = dict(zip(pivot.columns, colors))

    fig, ax = plt.subplots(figsize=(10.2, 4.8))
    left = np.zeros(len(pivot))
    y = np.arange(len(pivot))
    for taxon in pivot.columns:
        vals = pivot[taxon].to_numpy()
        ax.barh(
            y,
            vals,
            left=left,
            color=color_map[taxon],
            edgecolor="white",
            linewidth=0.8,
            height=0.62,
            label=taxon,
        )
        for idx, value in enumerate(vals):
            if value >= 0.085:
                ax.text(left[idx] + value / 2, idx, f"{value:.0%}", ha="center", va="center", fontsize=7, color="white")
        left += vals

    ax.set_yticks(y)
    ax.set_yticklabels(pivot.index)
    ax.set_xlim(0, 1)
    ax.set_xlabel("Share among displayed dominant taxa")
    ax.xaxis.set_major_formatter(mpl.ticker.PercentFormatter(1.0))
    ax.grid(axis="x", color=PALETTE["grid"], linewidth=0.9)
    ax.set_axisbelow(True)
    add_panel_title(
        ax,
        "Community-type dominant taxa composition",
        "Horizontal stacked-bar adaptation of the reference composition template.",
    )
    ax.legend(
        ncol=3,
        frameon=False,
        bbox_to_anchor=(0.5, -0.22),
        loc="upper center",
        fontsize=8,
        handlelength=1.1,
        columnspacing=1.2,
    )
    export_figure(
        fig,
        "Y02_community_type_stacked_composition",
        "Yuting horizontal stacked-bar template",
        data_source,
        "Converted community-type top-taxa table into a publication-style horizontal stacked composition plot.",
    )


def figure_ecological_network() -> None:
    edge_source = "08_ecological_modules_and_network/processed/npj_ecological_network_selected_edges.csv"
    evidence_source = "14_joint_core_evidence_map/processed/npj_integrated_feature_level_evidence_map.csv"
    edges = read_csv(edge_source)
    evidence = read_csv(evidence_source)
    edges["selected_edge_bool"] = bool_series(edges["selected_edge"])
    edges["abs_r"] = pd.to_numeric(edges["abs_r"], errors="coerce").fillna(0)
    edges["r"] = pd.to_numeric(edges["r"], errors="coerce").fillna(0)
    selected_edges = edges[edges["selected_edge_bool"]].sort_values("abs_r", ascending=False).copy()

    score_by_taxon = (
        evidence.assign(multi_evidence_score=pd.to_numeric(evidence["multi_evidence_score"], errors="coerce").fillna(0))
        .groupby("tax_label")["multi_evidence_score"]
        .max()
        .to_dict()
    )

    pre_graph = nx.Graph()
    for _, row in selected_edges.head(300).iterrows():
        pre_graph.add_edge(str(row["taxon_1"]), str(row["taxon_2"]), weight=float(row["abs_r"]), r=float(row["r"]))
    if pre_graph.number_of_nodes() == 0:
        raise RuntimeError("No ecological network edges were available for plotting.")
    largest_component = max(nx.connected_components(pre_graph), key=len)
    top_edges = selected_edges[
        selected_edges["taxon_1"].astype(str).isin(largest_component)
        & selected_edges["taxon_2"].astype(str).isin(largest_component)
    ].head(135)

    graph = nx.Graph()
    module_by_node: dict[str, str] = {}
    for _, row in top_edges.iterrows():
        n1 = str(row["taxon_1"])
        n2 = str(row["taxon_2"])
        graph.add_edge(n1, n2, weight=float(row["abs_r"]), r=float(row["r"]))
        module_by_node.setdefault(n1, str(row["module_1"]))
        module_by_node.setdefault(n2, str(row["module_2"]))

    modules = sorted(set(module_by_node.values()))
    module_palette = dict(zip(modules, sns.color_palette("Set2", n_colors=len(modules))))
    pos = nx.kamada_kawai_layout(graph, weight="weight")

    fig, (ax, info_ax) = plt.subplots(
        1,
        2,
        figsize=(11.8, 8.8),
        gridspec_kw={"width_ratios": [4.9, 1.45], "wspace": 0.04},
    )
    ax.set_facecolor("white")
    for u, v, attrs in graph.edges(data=True):
        x1, y1 = pos[u]
        x2, y2 = pos[v]
        color = PALETTE["red"] if attrs["r"] >= 0 else PALETTE["blue"]
        width = 0.35 + attrs["weight"] * 4.2
        ax.plot([x1, x2], [y1, y2], color=color, linewidth=width, alpha=0.34, zorder=1)

    degrees = dict(graph.degree())
    for module in modules:
        nodes = [n for n in graph.nodes if module_by_node.get(n) == module]
        xy = np.array([pos[n] for n in nodes])
        sizes = [80 + 34 * degrees[n] + 22 * score_by_taxon.get(n, 0) for n in nodes]
        ax.scatter(
            xy[:, 0],
            xy[:, 1],
            s=sizes,
            color=[module_palette[module]],
            edgecolor="white",
            linewidth=0.75,
            alpha=0.93,
            label=module,
            zorder=3,
        )

    ax.axis("off")
    ax.margins(0.14)
    ax.set_aspect("equal", adjustable="datalim")
    add_panel_title(
        ax,
        "Ecological co-occurrence network: main strong-edge component",
        "Node color denotes ecological module; node size blends selected degree and integrated evidence score.",
    )
    info_ax.axis("off")
    info_ax.text(0, 0.98, "Top hubs", ha="left", va="top", fontsize=10, fontweight="bold", color=PALETTE["navy"])
    label_rank = sorted(graph.nodes, key=lambda n: (degrees[n], score_by_taxon.get(n, 0)), reverse=True)[:12]
    y_cursor = 0.925
    for node in label_rank:
        module = module_by_node.get(node, "")
        info_ax.scatter(0.02, y_cursor, s=70, color=module_palette.get(module, "#BBBBBB"), edgecolor="white", linewidth=0.7)
        info_ax.text(
            0.08,
            y_cursor,
            f"{ellipsize_label(node, 24)}  ({module}, d={degrees[node]})",
            ha="left",
            va="center",
            fontsize=7.1,
            color=PALETTE["navy"],
        )
        y_cursor -= 0.044
    y_cursor -= 0.02
    info_ax.text(0, y_cursor, "Legend", ha="left", va="top", fontsize=9, fontweight="bold", color=PALETTE["navy"])
    y_cursor -= 0.06
    for module in modules:
        info_ax.scatter(0.02, y_cursor, s=60, color=module_palette[module], edgecolor="white", linewidth=0.7)
        info_ax.text(0.08, y_cursor, module, ha="left", va="center", fontsize=7.3, color=PALETTE["navy"])
        y_cursor -= 0.036
    info_ax.plot([0.0, 0.12], [y_cursor, y_cursor], color=PALETTE["red"], lw=2.8, alpha=0.6)
    info_ax.text(0.15, y_cursor, "Positive edge", ha="left", va="center", fontsize=7.3, color=PALETTE["navy"])
    y_cursor -= 0.04
    info_ax.plot([0.0, 0.12], [y_cursor, y_cursor], color=PALETTE["blue"], lw=2.8, alpha=0.6)
    info_ax.text(0.15, y_cursor, "Negative edge", ha="left", va="center", fontsize=7.3, color=PALETTE["navy"])
    info_ax.set_xlim(0, 1)
    info_ax.set_ylim(0, 1)
    export_figure(
        fig,
        "Y03_ecological_module_network",
        "Yuting NC-style ggraph network template",
        f"{edge_source}; {evidence_source}",
        "Translated the ggraph network idea into a dependency-light NetworkX/matplotlib module network.",
    )


def figure_integrated_tri_heatmap() -> None:
    data_source = "14_joint_core_evidence_map/processed/npj_integrated_feature_level_evidence_map.csv"
    df = read_csv(data_source)
    df["multi_evidence_score"] = pd.to_numeric(df["multi_evidence_score"], errors="coerce").fillna(0)
    df["evidence_domain_count"] = pd.to_numeric(df["evidence_domain_count"], errors="coerce").fillna(0)
    df["prevalence"] = pd.to_numeric(df["prevalence"], errors="coerce").fillna(0)
    top = (
        df.sort_values(["priority_tier", "multi_evidence_score", "evidence_domain_count", "prevalence"], ascending=[True, False, False, False])
        .drop_duplicates("tax_label")
        .head(26)
        .copy()
    )

    evidence_cols = {
        "LEfSe\nrecurrent": "evidence_lefse_recurrent4",
        "CLR\nrecurrent": "evidence_clr_recurrent2",
        "CLR\nFDR": "evidence_clr_fdr_exposure",
        "Module\nsignal": "evidence_module_nominal",
        "Module\nFDR": "evidence_module_fdr_global",
        "Network\nhub": "evidence_network_hub",
        "Mediation\nnominal": "mediation_nominal_support",
    }
    score_norm = Normalize(vmin=top["multi_evidence_score"].min(), vmax=max(top["multi_evidence_score"].max(), 1))
    evidence_palette = sns.color_palette("Set2", n_colors=len(evidence_cols))

    fig, ax = plt.subplots(figsize=(9.3, 10.5))
    n_rows = len(top)
    n_cols = len(evidence_cols)
    for row_idx, (_, row) in enumerate(top.iloc[::-1].iterrows()):
        y = row_idx
        score_color = SCORE_CMAP(score_norm(row["multi_evidence_score"]))
        for col_idx, (_, col_name) in enumerate(evidence_cols.items()):
            x = col_idx
            yes = bool_series(pd.Series([row.get(col_name, False)])).iloc[0]
            upper_color = evidence_palette[col_idx] if yes else "#F3F4F6"
            lower = Polygon([(x - 0.5, y - 0.5), (x + 0.5, y - 0.5), (x - 0.5, y + 0.5)], closed=True)
            upper = Polygon([(x + 0.5, y + 0.5), (x + 0.5, y - 0.5), (x - 0.5, y + 0.5)], closed=True)
            lower.set_facecolor(score_color)
            upper.set_facecolor(upper_color)
            for patch in (lower, upper):
                patch.set_edgecolor("white")
                patch.set_linewidth(0.8)
                ax.add_patch(patch)
            if yes:
                ax.text(x + 0.18, y + 0.13, "1", ha="center", va="center", fontsize=6.5, color="#111827")

    ax.set_xlim(-0.5, n_cols - 0.5)
    ax.set_ylim(-0.5, n_rows - 0.5)
    ax.set_xticks(range(n_cols))
    ax.set_xticklabels(list(evidence_cols.keys()), fontsize=8)
    ax.set_yticks(range(n_rows))
    ax.set_yticklabels(top.iloc[::-1]["tax_label"], fontsize=8)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    add_panel_title(
        ax,
        "Integrated taxon evidence map",
        "Upper triangle marks evidence-domain support; lower triangle carries the row-level multi-evidence score.",
    )
    sm = mpl.cm.ScalarMappable(cmap=SCORE_CMAP, norm=score_norm)
    cbar = fig.colorbar(sm, ax=ax, fraction=0.035, pad=0.02)
    cbar.set_label("Multi-evidence score", fontsize=9)
    export_figure(
        fig,
        "Y04_integrated_evidence_split_tile_heatmap",
        "Yuting split/diagonal heatmap template",
        data_source,
        "Recreated the diagonal/split heatmap idea for integrated recurrent-taxon evidence domains.",
    )


def curved_segment(ax: plt.Axes, start: tuple[float, float], end: tuple[float, float], color: str, lw: float, alpha: float) -> None:
    x0, y0 = start
    x1, y1 = end
    dx = x1 - x0
    path = MplPath(
        [
            (x0, y0),
            (x0 + dx * 0.45, y0),
            (x1 - dx * 0.45, y1),
            (x1, y1),
        ],
        [MplPath.MOVETO, MplPath.CURVE4, MplPath.CURVE4, MplPath.CURVE4],
    )
    patch = PathPatch(path, facecolor="none", edgecolor=color, lw=lw, alpha=alpha, capstyle="round")
    ax.add_patch(patch)


def level_positions(values: pd.Series, weights: pd.Series) -> dict[str, float]:
    table = (
        pd.DataFrame({"value": values.astype(str), "weight": weights})
        .groupby("value", as_index=False)["weight"]
        .sum()
        .sort_values("weight", ascending=False)
    )
    if len(table) == 1:
        return {table.iloc[0]["value"]: 0.5}
    ys = np.linspace(0.08, 0.92, len(table))
    return dict(zip(table["value"], ys))


def figure_mediation_ribbon() -> None:
    data_source = "12_mediation_analysis/processed/npj_mediation_top_pathways.csv"
    df = read_csv(data_source)
    df["indirect_p"] = pd.to_numeric(df["indirect_p"], errors="coerce")
    df["indirect_beta"] = pd.to_numeric(df["indirect_beta"], errors="coerce")
    df = df.dropna(subset=["indirect_p"]).sort_values("indirect_p").head(14).copy()
    df["weight"] = -np.log10(df["indirect_p"].clip(lower=1e-12))
    df["weight_scaled"] = 1.0 + (df["weight"] - df["weight"].min()) / max(df["weight"].max() - df["weight"].min(), 1e-9) * 5.2

    levels = ["exposure_label", "mediator_label", "outcome_label"]
    positions = {level: level_positions(df[level], df["weight"]) for level in levels}
    x_map = {"exposure_label": 0.0, "mediator_label": 1.0, "outcome_label": 2.0}
    node_weight: dict[tuple[str, str], float] = defaultdict(float)
    for _, row in df.iterrows():
        for level in levels:
            node_weight[(level, str(row[level]))] += float(row["weight"])

    fig, ax = plt.subplots(figsize=(11.8, 8.2))
    for _, row in df.iterrows():
        color = PALETTE["red"] if row["indirect_beta"] >= 0 else PALETTE["blue"]
        y0 = positions["exposure_label"][str(row["exposure_label"])]
        y1 = positions["mediator_label"][str(row["mediator_label"])]
        y2 = positions["outcome_label"][str(row["outcome_label"])]
        curved_segment(ax, (0.05, y0), (0.95, y1), color, row["weight_scaled"], 0.26)
        curved_segment(ax, (1.05, y1), (1.95, y2), color, row["weight_scaled"], 0.26)

    level_colors = {"exposure_label": PALETTE["gold"], "mediator_label": PALETTE["cyan"], "outcome_label": PALETTE["green"]}
    for level in levels:
        x = x_map[level]
        for label, y in positions[level].items():
            size = 170 + node_weight[(level, label)] * 35
            ax.scatter(x, y, s=size, color=level_colors[level], edgecolor="white", linewidth=1.0, zorder=5)
            bbox = dict(boxstyle="round,pad=0.18", facecolor="white", edgecolor="none", alpha=0.86)
            ha = "right" if level == "exposure_label" else "left"
            offset = -0.08 if level == "exposure_label" else 0.085
            if level == "mediator_label":
                ha = "left"
                offset = 0.135
                ax.text(
                    x + offset,
                    y,
                    wrap_label(label, 16),
                    ha=ha,
                    va="center",
                    fontsize=6.8,
                    color=PALETTE["navy"],
                    bbox=bbox,
                    zorder=6,
                )
            else:
                ax.text(
                    x + offset,
                    y,
                    wrap_label(label, 18),
                    ha=ha,
                    va="center",
                    fontsize=8,
                    color=PALETTE["navy"],
                    bbox=bbox,
                    zorder=6,
                )

    for x, title in [(0, "Diet index"), (1, "Mediator"), (2, "Oral health outcome")]:
        ax.text(x, 0.985, title, ha="center", va="bottom", fontsize=9.2, fontweight="bold", color=PALETTE["navy"])
    ax.set_xlim(-0.56, 2.72)
    ax.set_ylim(0, 1)
    ax.axis("off")
    add_panel_title(
        ax,
        "Top exploratory mediation paths",
        "Line width is -log10(indirect P); color denotes the direction of the indirect association.",
    )
    ax.legend(
        handles=[
            Line2D([0], [0], color=PALETTE["red"], lw=4, alpha=0.45, label="Positive indirect effect"),
            Line2D([0], [0], color=PALETTE["blue"], lw=4, alpha=0.45, label="Negative indirect effect"),
        ],
        frameon=False,
        loc="lower center",
        ncol=2,
    )
    export_figure(
        fig,
        "Y05_mediation_pathway_ribbon",
        "Yuting Sankey/flow visualization notebook",
        data_source,
        "Adapted the Sankey/flow concept into a static exploratory mediation pathway ribbon figure.",
    )


def figure_key_taxa_lollipop() -> None:
    data_source = "20_key_taxa_dose_response/processed/npj_key_taxa_dose_response_results.csv"
    df = read_csv(data_source)
    for col in ["beta_linear", "p_linear", "p_spline_overall", "p_fdr_spline"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df["p_best"] = df[["p_linear", "p_spline_overall"]].min(axis=1)
    df = df.sort_values(["p_best", "p_fdr_spline"]).head(30).copy()
    df["label"] = df["exposure_label"] + "  |  " + df["tax_label"]
    df = df.iloc[::-1].reset_index(drop=True)
    y = np.arange(len(df))
    beta_max = np.nanmax(np.abs(df["beta_linear"].to_numpy()))
    beta_max = 0.15 if not np.isfinite(beta_max) or beta_max == 0 else beta_max
    norm = TwoSlopeNorm(vmin=-beta_max, vcenter=0, vmax=beta_max)
    strength = -np.log10(df["p_best"].clip(lower=1e-12))
    sizes = 36 + np.clip(strength, 0, 5) * 30

    fig, ax = plt.subplots(figsize=(9.3, 8.6))
    ax.axvline(0, color=PALETTE["navy"], lw=0.9, alpha=0.75)
    for yi, beta in zip(y, df["beta_linear"]):
        ax.plot([0, beta], [yi, yi], color=PALETTE["grid"], lw=1.5, zorder=1)
    sc = ax.scatter(
        df["beta_linear"],
        y,
        s=sizes,
        c=df["beta_linear"],
        cmap=DIV_CMAP,
        norm=norm,
        edgecolor=np.where(df["p_fdr_spline"] < 0.05, "#111827", "white"),
        linewidth=np.where(df["p_fdr_spline"] < 0.05, 1.25, 0.65),
        zorder=3,
    )
    ax.set_yticks(y)
    ax.set_yticklabels(df["label"], fontsize=8)
    ax.set_xlabel("Linear CLR beta per 1-SD diet index")
    ax.grid(axis="x", color=PALETTE["grid"], linewidth=0.9)
    ax.set_axisbelow(True)
    add_panel_title(
        ax,
        "Key-taxon dose-response ranking",
        "Point size reflects the strongest linear or spline evidence; black outline marks spline FDR < 0.05.",
    )
    cbar = fig.colorbar(sc, ax=ax, fraction=0.035, pad=0.02)
    cbar.set_label("Linear beta", fontsize=9)
    for pval, label in [(0.05, "P=0.05"), (0.01, "P=0.01"), (0.001, "P=0.001")]:
        ax.scatter([], [], s=36 + min(-np.log10(pval), 5) * 30, facecolor="white", edgecolor=PALETTE["navy"], label=label)
    ax.legend(title="Evidence size", frameon=False, loc="lower right", fontsize=8, title_fontsize=9)
    export_figure(
        fig,
        "Y06_key_taxa_dose_response_lollipop",
        "Yuting Nature-Cancer multi-indicator ranking template",
        data_source,
        "Adapted a multi-indicator ranking idea to key-taxon dose-response effects.",
    )


def write_manifest() -> None:
    manifest_df = pd.DataFrame(manifest)
    manifest_csv = OUT_DIR / "yuting_style_visualization_manifest.csv"
    manifest_df.to_csv(manifest_csv, index=False, encoding="utf-8-sig")
    readme = OUT_DIR / "README_yuting_style_visualizations.md"
    lines = [
        "# Yuting-style visualization adaptation",
        "",
        "This folder contains additional figures generated for the current NHANES diet index and oral microbiome study.",
        "The script reads only existing processed results and does not change any statistical model outputs.",
        "",
        "## Reference ideas transferred",
        "",
        "| Output | Reference style | Current study data | Use |",
        "|---|---|---|---|",
    ]
    for row in manifest:
        lines.append(
            f"| `{row['figure']}` | `{row['source_style']}` | `{row['data_source']}` | {row['note']} |"
        )
    lines.extend(
        [
            "",
            "## Regeneration",
            "",
            "Run from the project root:",
            "",
            "```powershell",
            "python .\\visualize_yuting_style_extensions.py",
            "```",
            "",
            "Manifest: `yuting_style_visualization_manifest.csv`",
        ]
    )
    readme.write_text("\n".join(lines), encoding="utf-8")

    usage = OUT_DIR / "figure_style_usage_zh.md"
    usage_lines = [
        "# 本研究直接采用的玉婷代码图形风格",
        "",
        "以下 6 类图形风格已直接应用到当前 NHANES 膳食指数与口腔微生物研究中。图件均由本研究已有 processed 结果表生成，不改变任何统计模型结果。",
        "",
        "| 图件 | 直接采用的风格 | 建议用途 |",
        "|---|---|---|",
        "| `Y01_da_validation_balloonplot` | 差异菌属验证气泡矩阵图 | 方法一致性验证、差异菌属跨膳食指数证据展示，可作为补充图或稳健性图件。 |",
        "| `Y02_community_type_stacked_composition` | community type dominant taxa 横向堆叠组成图 | 展示不同口腔微生物 community type 的优势菌属组成。 |",
        "| `Y03_ecological_module_network` | 生态模块强相关网络图 | 展示生态模块、强共现边和核心网络菌属，可用于生态机制图。 |",
        "| `Y04_integrated_evidence_split_tile_heatmap` | 综合证据 split-tile/对角热图 | 汇总 LEfSe、CLR、模块、网络、中介等多证据域，适合核心证据整合图。 |",
        "| `Y05_mediation_pathway_ribbon` | 探索性中介路径 ribbon/桑基风格图 | 展示膳食指数、微生物中介、口腔健康结局之间的探索性路径。 |",
        "| `Y06_key_taxa_dose_response_lollipop` | 关键菌属剂量反应 lollipop 排序图 | 展示关键菌属与膳食指数之间的线性/非线性剂量反应强度。 |",
        "",
        "## 输出位置",
        "",
        "- PNG/PDF 图件：当前文件夹",
        "- 总览图：`Y00_direct_style_contact_sheet.png`",
        "- 索引表：`yuting_style_visualization_manifest.csv`",
        "",
        "## 再生成",
        "",
        "```powershell",
        "python .\\visualize_yuting_style_extensions.py",
        "```",
    ]
    usage.write_text("\n".join(usage_lines), encoding="utf-8")


def make_contact_sheet() -> None:
    specs = [
        ("Y01_da_validation_balloonplot.png", "Y01 DA validation balloon matrix"),
        ("Y02_community_type_stacked_composition.png", "Y02 Community-type stacked composition"),
        ("Y03_ecological_module_network.png", "Y03 Ecological module network"),
        ("Y04_integrated_evidence_split_tile_heatmap.png", "Y04 Integrated split-tile heatmap"),
        ("Y05_mediation_pathway_ribbon.png", "Y05 Mediation pathway ribbon"),
        ("Y06_key_taxa_dose_response_lollipop.png", "Y06 Key-taxa dose-response lollipop"),
    ]
    thumb_w, thumb_h = 760, 520
    pad = 36
    title_h = 72
    sheet_w = pad * 3 + thumb_w * 2
    sheet_h = pad * 4 + (thumb_h + title_h) * 3
    sheet = Image.new("RGB", (sheet_w, sheet_h), "white")
    draw = ImageDraw.Draw(sheet)
    try:
        font_title = ImageFont.truetype("arial.ttf", 28)
        font_label = ImageFont.truetype("arial.ttf", 22)
    except OSError:
        font_title = ImageFont.load_default()
        font_label = ImageFont.load_default()

    draw.text((pad, 16), "Publication figures for this study", fill=PALETTE["navy"], font=font_title)
    for idx, (filename, label) in enumerate(specs):
        row, col = divmod(idx, 2)
        x = pad + col * (thumb_w + pad)
        y = pad + 34 + row * (thumb_h + title_h + pad)
        img = Image.open(OUT_DIR / filename).convert("RGB")
        resample = getattr(Image, "Resampling", Image).LANCZOS
        img.thumbnail((thumb_w, thumb_h), resample)
        box = Image.new("RGB", (thumb_w, thumb_h), "#F8FAFC")
        box.paste(img, ((thumb_w - img.width) // 2, (thumb_h - img.height) // 2))
        sheet.paste(box, (x, y + title_h))
        draw.text((x, y + 24), label, fill=PALETTE["navy"], font=font_label)
        draw.rectangle((x, y + title_h, x + thumb_w, y + title_h + thumb_h), outline="#E5E7EB", width=2)
    sheet.save(OUT_DIR / "Y00_direct_style_contact_sheet.png", quality=95)


def main() -> None:
    figure_da_balloon()
    figure_community_stacked_bar()
    figure_ecological_network()
    figure_integrated_tri_heatmap()
    figure_mediation_ribbon()
    figure_key_taxa_lollipop()
    write_manifest()
    make_contact_sheet()
    print(f"Generated {len(manifest)} publication visualization panels in: {OUT_DIR}")


if __name__ == "__main__":
    main()
