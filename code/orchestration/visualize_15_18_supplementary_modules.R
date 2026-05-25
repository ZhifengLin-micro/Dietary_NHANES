options(stringsAsFactors = FALSE)

args_full <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = TRUE)
  project_root <- dirname(script_path)
} else {
  project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
}
project_lib <- file.path(dirname(project_root), ".Rlib")
if (dir.exists(project_lib)) .libPaths(c(project_lib, .libPaths()))

required_pkgs <- c("data.table", "vegan")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
suppressPackageStartupMessages({
  library(data.table)
  library(vegan)
})

theme_cols <- list(
  blue = "#2A6F97",
  cyan = "#74A9CF",
  pale = "#F6E8C3",
  orange = "#F4A261",
  red = "#B2182B",
  navy = "#1F2937",
  grey = "#6B7280",
  grid = "#E8EEF2"
)
div_pal <- grDevices::colorRampPalette(c("#3B4CC0", "#D8ECF3", "#F6E8C3", "#F4A261", "#B2182B"))(101)
exposure_order <- c("HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI")
alpha_order <- c("observed_asv", "faith_pd", "shannon_index", "inverse_simpson_index")

dirs <- list(
  da = file.path(project_root, "15_da_validation_ANCOMBC2_MaAsLin3"),
  ctype = file.path(project_root, "16_community_typing"),
  pca = file.path(project_root, "17_diet_PCA_patterns"),
  module = file.path(project_root, "18_core_module_scores"),
  central = file.path(project_root, "12_figures_tables_npj", "figures_15_18_visualizations")
)
dir.create(dirs$central, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(path) read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
num <- function(x) suppressWarnings(as.numeric(as.character(x)))
bool <- function(x) as.logical(toupper(as.character(x)))
clip <- function(x, lo, hi) pmax(lo, pmin(hi, x))

copy_to_central <- function(path) {
  file.copy(path, file.path(dirs$central, basename(path)), overwrite = TRUE)
}

save_plot <- function(path_png, path_pdf, width_px, height_px, plot_fun) {
  png(path_png, width = width_px, height = height_px, res = 300)
  plot_fun()
  dev.off()
  pdf(path_pdf, width = width_px / 300, height = height_px / 300, family = "sans")
  plot_fun()
  dev.off()
  copy_to_central(path_png)
  copy_to_central(path_pdf)
}

value_to_col <- function(x, rng = NULL) {
  if (is.null(rng)) rng <- range(x, na.rm = TRUE)
  if (!all(is.finite(rng))) rng <- c(-1, 1)
  if (diff(rng) == 0) rng <- rng + c(-1e-6, 1e-6)
  idx <- round((x - rng[1]) / diff(rng) * 100) + 1
  div_pal[clip(idx, 1, 101)]
}

add_clean_grid <- function(nx, ny) {
  abline(v = seq(0.5, nx + 0.5, by = 1), col = "white", lwd = 0.8)
  abline(h = seq(0.5, ny + 0.5, by = 1), col = "white", lwd = 0.8)
}

plot_matrix_heatmap <- function(mat, title, zlab, digits = 2) {
  mat <- as.matrix(mat)
  rng <- range(mat, na.rm = TRUE)
  if (!all(is.finite(rng))) rng <- c(-1, 1)
  if (diff(rng) == 0) rng <- rng + c(-1e-6, 1e-6)
  par(mar = c(7.5, 9.5, 4, 5), family = "sans")
  image(seq_len(ncol(mat)), seq_len(nrow(mat)), t(mat[nrow(mat):1, , drop = FALSE]), col = div_pal, axes = FALSE, xlab = "", ylab = "", main = title, zlim = rng)
  axis(1, at = seq_len(ncol(mat)), labels = colnames(mat), las = 2, cex.axis = 0.75)
  axis(2, at = seq_len(nrow(mat)), labels = rev(rownames(mat)), las = 1, cex.axis = 0.75)
  add_clean_grid(ncol(mat), nrow(mat))
  if (nrow(mat) <= 35 && ncol(mat) <= 12) {
    for (i in seq_len(nrow(mat))) {
      for (j in seq_len(ncol(mat))) {
        val <- mat[rev(seq_len(nrow(mat)))[i], j]
        if (!is.na(val)) text(j, i, sprintf(paste0("%.", digits, "f"), val), cex = 0.45, col = theme_cols$navy)
      }
    }
  }
  legend_x <- ncol(mat) + 0.65
  legend_y <- seq(0.65, nrow(mat) + 0.35, length.out = 101)
  rasterImage(as.raster(matrix(rev(div_pal), ncol = 1)), legend_x, min(legend_y), legend_x + 0.22, max(legend_y), xpd = NA)
  text(legend_x + 0.35, max(legend_y), sprintf("%.2f", rng[2]), adj = 0, cex = 0.62, xpd = NA)
  text(legend_x + 0.35, min(legend_y), sprintf("%.2f", rng[1]), adj = 0, cex = 0.62, xpd = NA)
  text(legend_x + 0.11, max(legend_y) + 0.35, zlab, cex = 0.67, xpd = NA)
}

convex_hull <- function(x, y) {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 3) return(NULL)
  idx <- grDevices::chull(x[ok], y[ok])
  data.frame(x = x[ok][idx], y = y[ok][idx])
}

# Module 15: DA validation -----------------------------------------------------
da_summary <- read_csv(file.path(dirs$da, "processed", "npj_da_validation_summary_by_diet.csv"))
da_validation <- data.table::as.data.table(read_csv(file.path(dirs$da, "processed", "npj_da_validation_cross_method_consistency.csv")))
da_validation[, p_min := pmin(num(p_value_continuous), num(p_value_q4), na.rm = TRUE)]
da_validation[, abs_beta := abs(num(beta_continuous))]
da_sig <- da_validation[bool(validated_nominal_both) %in% TRUE]
if (nrow(da_sig) == 0) da_sig <- da_validation[order(p_min)][seq_len(min(40, .N))]
top_taxa <- unique(da_sig[order(p_min)]$tax_label)[seq_len(min(28, length(unique(da_sig$tax_label))))]
da_plot <- da_sig[tax_label %in% top_taxa, .(
  beta = mean(num(beta_continuous), na.rm = TRUE),
  p_value = min(p_min, na.rm = TRUE),
  n_signal = .N
), by = .(tax_label, exposure_label)]
taxa_order <- rev(unique(da_sig[order(p_min)]$tax_label)[unique(da_sig[order(p_min)]$tax_label) %in% top_taxa])

save_plot(
  file.path(dirs$da, "figures", "figure15_da_validation_summary_counts.png"),
  file.path(dirs$da, "figures", "figure15_da_validation_summary_counts.pdf"),
  2200, 1500,
  function() {
    par(mar = c(6.5, 5, 4, 1), family = "sans")
    da_summary <- da_summary[match(exposure_order, da_summary$exposure_label), ]
    mat <- rbind(num(da_summary$n_nominal_both), num(da_summary$n_fdr_any))
    colnames(mat) <- da_summary$exposure_label
    bp <- barplot(mat, beside = TRUE, col = c(theme_cols$blue, theme_cols$orange), border = NA, ylim = c(0, max(mat, na.rm = TRUE) + 5), las = 2, ylab = "Number of validated taxa", main = "Cross-method differential abundance validation")
    text(bp, mat + 0.8, labels = mat, cex = 0.7)
    legend("topright", legend = c("Nominal in both layers", "FDR-level in either layer"), fill = c(theme_cols$blue, theme_cols$orange), bty = "n", cex = 0.8)
  }
)

save_plot(
  file.path(dirs$da, "figures", "figure15_da_validation_top_taxa_bubble.png"),
  file.path(dirs$da, "figures", "figure15_da_validation_top_taxa_bubble.pdf"),
  3000, 2600,
  function() {
    par(mar = c(7.5, 11, 4, 5), family = "sans")
    plot(NA, NA, xlim = c(0.5, length(exposure_order) + 0.5), ylim = c(0.5, length(taxa_order) + 0.5), xaxt = "n", yaxt = "n", xlab = "", ylab = "", main = "Validated diet-associated taxa across indices")
    axis(1, at = seq_along(exposure_order), labels = exposure_order, las = 2, cex.axis = 0.78)
    axis(2, at = seq_along(taxa_order), labels = taxa_order, las = 1, cex.axis = 0.68)
    abline(v = seq_along(exposure_order), col = theme_cols$grid)
    abline(h = seq_along(taxa_order), col = theme_cols$grid)
    rng <- range(da_plot$beta, na.rm = TRUE)
    x <- match(da_plot$exposure_label, exposure_order)
    y <- match(da_plot$tax_label, taxa_order)
    score <- pmin(-log10(da_plot$p_value), 6)
    points(x, y, pch = 21, bg = value_to_col(da_plot$beta, rng), col = "#222222", cex = 0.9 + score * 0.28, lwd = 0.5)
    text(x, y, labels = da_plot$n_signal, cex = 0.45, col = "#111111")
    legend("topright", legend = c("larger = stronger evidence", "number = repeated features"), pch = c(21, NA), pt.bg = c(theme_cols$orange, NA), bty = "n", cex = 0.72)
    mtext("Diet index", side = 1, line = 5.7)
    mtext("Validated recurrent taxa", side = 2, line = 8.5)
  }
)

# Module 16: Community typing --------------------------------------------------
assignments <- read_csv(file.path(dirs$ctype, "processed", "npj_community_type_assignments.csv"))
centroids <- data.table::as.data.table(read_csv(file.path(dirs$ctype, "processed", "npj_community_type_taxa_centroids_long.csv")))
rel_mat <- readRDS(file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_relative_filtered_matrix.rds"))
rel_mat$SEQN <- as.character(rel_mat$SEQN)
ids <- intersect(assignments$SEQN, rel_mat$SEQN)
rel_sub <- rel_mat[match(ids, rel_mat$SEQN), , drop = FALSE]
assign_sub <- assignments[match(ids, assignments$SEQN), , drop = FALSE]
rel_cols <- setdiff(names(rel_sub), "SEQN")
rel_x <- as.matrix(rel_sub[, rel_cols, drop = FALSE])
storage.mode(rel_x) <- "numeric"
rel_x[is.na(rel_x)] <- 0
bray <- vegan::vegdist(sqrt(rel_x), method = "bray")
pcoa <- stats::cmdscale(bray, eig = TRUE, k = 2)
pcoa_df <- data.frame(SEQN = ids, Axis1 = pcoa$points[, 1], Axis2 = pcoa$points[, 2], community_type = assign_sub$community_type)
variance <- pcoa$eig / sum(abs(pcoa$eig))
ctype_cols <- setNames(c(theme_cols$blue, theme_cols$orange, theme_cols$red, "#66A61E")[seq_along(unique(assign_sub$community_type))], sort(unique(assign_sub$community_type)))

save_plot(
  file.path(dirs$ctype, "figures", "figure16_community_type_pcoa_convex_hull.png"),
  file.path(dirs$ctype, "figures", "figure16_community_type_pcoa_convex_hull.pdf"),
  2300, 1900,
  function() {
    par(mar = c(5, 5, 4, 1), family = "sans")
    plot(pcoa_df$Axis1, pcoa_df$Axis2, pch = 16, cex = 0.35, col = adjustcolor(ctype_cols[pcoa_df$community_type], alpha.f = 0.45), xlab = sprintf("PCoA1 (%.1f%%)", variance[1] * 100), ylab = sprintf("PCoA2 (%.1f%%)", variance[2] * 100), main = "Oral microbiome community types")
    grid(col = theme_cols$grid)
    for (ct in names(ctype_cols)) {
      h <- convex_hull(pcoa_df$Axis1[pcoa_df$community_type == ct], pcoa_df$Axis2[pcoa_df$community_type == ct])
      if (!is.null(h)) polygon(h$x, h$y, border = ctype_cols[ct], col = adjustcolor(ctype_cols[ct], alpha.f = 0.12), lwd = 1.5)
    }
    legend("topright", legend = names(ctype_cols), col = ctype_cols, pch = 16, bty = "n")
  }
)

top_cent <- centroids[, .(mean_abundance = mean(num(mean_relative_abundance), na.rm = TRUE)), by = tax_label][order(-mean_abundance)][1:10]
comp <- centroids[tax_label %in% top_cent$tax_label, .(mean_abundance = sum(num(mean_relative_abundance), na.rm = TRUE)), by = .(community_type, tax_label)]
comp_wide <- data.table::dcast(comp, tax_label ~ community_type, value.var = "mean_abundance", fill = 0)
comp_mat <- as.matrix(comp_wide[, -1, with = FALSE])
rownames(comp_mat) <- comp_wide$tax_label
for (j in seq_len(ncol(comp_mat))) {
  total_top <- sum(comp_mat[, j], na.rm = TRUE)
  comp_mat[, j] <- comp_mat[, j] / max(total_top, 1e-12)
}
save_plot(
  file.path(dirs$ctype, "figures", "figure16_community_type_top_taxa_composition.png"),
  file.path(dirs$ctype, "figures", "figure16_community_type_top_taxa_composition.pdf"),
  2100, 1500,
  function() {
    par(mar = c(5, 11, 4, 7), family = "sans")
    cols <- grDevices::colorRampPalette(c("#2A6F97", "#74A9CF", "#F6E8C3", "#F4A261", "#B2182B"))(nrow(comp_mat))
    barplot(comp_mat, horiz = TRUE, col = cols, border = NA, xlab = "Relative composition among top taxa", main = "Dominant taxa signatures by community type", las = 1)
    legend("right", inset = -0.22, legend = rownames(comp_mat), fill = cols, bty = "n", cex = 0.58, xpd = NA)
  }
)

# Module 17: Diet PCA ----------------------------------------------------------
pca_var <- read_csv(file.path(dirs$pca, "processed", "npj_diet_pca_variance.csv"))
pca_load <- read_csv(file.path(dirs$pca, "processed", "npj_diet_pca_loadings.csv"))
pca_alpha <- read_csv(file.path(dirs$pca, "processed", "npj_diet_pca_alpha_associations.csv"))
save_plot(
  file.path(dirs$pca, "figures", "figure17_diet_pca_loading_biplot.png"),
  file.path(dirs$pca, "figures", "figure17_diet_pca_loading_biplot.pdf"),
  2000, 1800,
  function() {
    par(mar = c(5, 5, 4, 1), family = "sans")
    x <- num(pca_load$PC1)
    y <- num(pca_load$PC2)
    plot(x, y, type = "n", xlim = range(x, 0) * 1.2, ylim = range(y, 0) * 1.2, xlab = sprintf("PC1 (%.1f%%)", num(pca_var$variance_explained[1]) * 100), ylab = sprintf("PC2 (%.1f%%)", num(pca_var$variance_explained[2]) * 100), main = "Diet index architecture: PCA loading map")
    abline(h = 0, v = 0, col = theme_cols$grid)
    grid(col = theme_cols$grid)
    arrows(0, 0, x, y, length = 0.08, lwd = 1.4, col = ifelse(x > 0, theme_cols$blue, theme_cols$red))
    points(x, y, pch = 21, bg = ifelse(x > 0, theme_cols$cyan, theme_cols$orange), col = theme_cols$navy, cex = 1.5)
    text(x, y, labels = pca_load$diet_index, pos = 3, cex = 0.8)
  }
)

alpha_forest_df <- pca_alpha[pca_alpha$PC %in% c("PC1", "PC2"), ]
alpha_forest_df$outcome <- factor(alpha_forest_df$outcome, levels = alpha_order)
save_plot(
  file.path(dirs$pca, "figures", "figure17_diet_pca_alpha_forest.png"),
  file.path(dirs$pca, "figures", "figure17_diet_pca_alpha_forest.pdf"),
  2200, 1500,
  function() {
    par(mfrow = c(1, 2), mar = c(5, 8, 4, 1), family = "sans")
    for (pc in c("PC1", "PC2")) {
      sub <- alpha_forest_df[alpha_forest_df$PC == pc, ]
      y <- seq_len(nrow(sub))
      beta <- num(sub$beta)
      se <- num(sub$se)
      xlim <- range(c(beta - 1.96 * se, beta + 1.96 * se, 0), na.rm = TRUE)
      plot(beta, y, xlim = xlim, ylim = c(0.5, nrow(sub) + 0.5), pch = 21, bg = theme_cols$blue, yaxt = "n", xlab = "Beta (95% CI)", ylab = "", main = paste0(pc, " and alpha diversity"))
      axis(2, at = y, labels = sub$outcome, las = 1, cex.axis = 0.75)
      abline(v = 0, col = theme_cols$grid, lwd = 1.2)
      segments(beta - 1.96 * se, y, beta + 1.96 * se, y, col = theme_cols$navy)
      points(beta, y, pch = 21, bg = ifelse(num(sub$p_value) < 0.05, theme_cols$orange, theme_cols$cyan), col = theme_cols$navy, cex = 1.2)
    }
  }
)

# Module 18: Core module scores ------------------------------------------------
module_diet <- read_csv(file.path(dirs$module, "processed", "npj_core_module_diet_associations.csv"))
module_alpha <- read_csv(file.path(dirs$module, "processed", "npj_core_module_alpha_associations.csv"))
bridge <- read_csv(file.path(dirs$module, "processed", "npj_core_module_bridge_diet_alpha.csv"))
module_order <- sort(unique(module_diet$module_id))
module_diet$module_id <- factor(module_diet$module_id, levels = rev(module_order))
module_diet$exposure_label <- factor(module_diet$exposure_label, levels = exposure_order)
save_plot(
  file.path(dirs$module, "figures", "figure18_core_module_diet_bubble.png"),
  file.path(dirs$module, "figures", "figure18_core_module_diet_bubble.pdf"),
  2400, 1700,
  function() {
    par(mar = c(7, 6, 4, 5), family = "sans")
    x <- as.numeric(module_diet$exposure_label)
    y <- as.numeric(module_diet$module_id)
    beta <- num(module_diet$beta)
    p <- num(module_diet$p_value)
    plot(NA, NA, xlim = c(0.5, length(exposure_order) + 0.5), ylim = c(0.5, length(module_order) + 0.5), xaxt = "n", yaxt = "n", xlab = "", ylab = "", main = "Core ecological modules associated with diet indices")
    axis(1, at = seq_along(exposure_order), labels = exposure_order, las = 2, cex.axis = 0.8)
    axis(2, at = seq_along(rev(module_order)), labels = rev(module_order), las = 1)
    abline(v = seq_along(exposure_order), col = theme_cols$grid)
    abline(h = seq_along(module_order), col = theme_cols$grid)
    size <- 1 + pmin(-log10(p), 5) * 0.35
    points(x, y, pch = 21, bg = value_to_col(beta), col = ifelse(p < 0.05, "#111111", "#8A8F98"), lwd = ifelse(p < 0.05, 1.1, 0.5), cex = size)
    text(x, y, labels = ifelse(p < 0.05, "*", ""), cex = 0.7)
    mtext("Diet index", side = 1, line = 5.4)
    mtext("Ecological module", side = 2, line = 4.2)
  }
)

bridge_counts <- if (nrow(bridge) > 0) {
  data.table::dcast(data.table::as.data.table(bridge), exposure_label ~ outcome, value.var = "module_id", fun.aggregate = length, fill = 0)
} else {
  data.frame(exposure_label = exposure_order)
}
missing_alpha <- setdiff(alpha_order, names(bridge_counts))
for (a in missing_alpha) bridge_counts[[a]] <- 0
bridge_counts <- bridge_counts[match(exposure_order, bridge_counts$exposure_label), c("exposure_label", alpha_order)]
bridge_mat <- as.matrix(bridge_counts[, alpha_order])
rownames(bridge_mat) <- bridge_counts$exposure_label
save_plot(
  file.path(dirs$module, "figures", "figure18_core_module_bridge_heatmap.png"),
  file.path(dirs$module, "figures", "figure18_core_module_bridge_heatmap.pdf"),
  1900, 1700,
  function() {
    plot_matrix_heatmap(bridge_mat, "Diet-module-alpha bridge evidence", "bridge count", 0)
  }
)

writeLines(c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "Visualization outputs generated for modules 15-18.",
  paste0("Central figure directory: ", dirs$central),
  "Module 15: summary bar plot and validated taxa bubble plot.",
  "Module 16: community type PCoA with convex hulls and taxa composition plot.",
  "Module 17: diet PCA loading biplot and alpha diversity forest plot.",
  "Module 18: module-diet bubble plot and diet-module-alpha bridge heatmap."
), file.path(project_root, "00_protocol_and_log", "npj_15_18_visualization_summary.txt"), useBytes = TRUE)

message("Visualizations for modules 15-18 completed.")
