options(stringsAsFactors = FALSE)

args_full <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = TRUE)
  project_root <- dirname(script_path)
} else {
  project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
}

module_dir <- file.path(project_root, "18_core_module_scores")
central_dir <- file.path(project_root, "12_figures_tables_npj", "figures_15_18_visualizations")
dir.create(central_dir, recursive = TRUE, showWarnings = FALSE)

read_csv <- function(path) read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
alpha_order <- c("observed_asv", "faith_pd", "shannon_index", "inverse_simpson_index")
exposure_order <- c("HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI")
pal <- grDevices::colorRampPalette(c("#F8FBFD", "#D8ECF3", "#74A9CF", "#2A6F97", "#B2182B"))(101)

bridge <- read_csv(file.path(module_dir, "processed", "npj_core_module_bridge_diet_alpha.csv"))
if (nrow(bridge) > 0) {
  tab <- as.data.frame.matrix(table(bridge$exposure_label, bridge$outcome))
  tab$exposure_label <- rownames(tab)
  rownames(tab) <- NULL
} else {
  tab <- data.frame(exposure_label = character(0))
}
for (a in setdiff(alpha_order, names(tab))) tab[[a]] <- 0
tab <- merge(data.frame(exposure_label = exposure_order), tab, by = "exposure_label", all.x = TRUE, sort = FALSE)
tab <- tab[match(exposure_order, tab$exposure_label), c("exposure_label", alpha_order), drop = FALSE]
for (a in alpha_order) tab[[a]][is.na(tab[[a]])] <- 0
mat <- as.matrix(tab[, alpha_order, drop = FALSE])
storage.mode(mat) <- "numeric"
rownames(mat) <- tab$exposure_label

plot_bridge <- function() {
  rng <- range(mat, na.rm = TRUE)
  if (!all(is.finite(rng))) rng <- c(0, 1)
  if (diff(rng) == 0) rng <- rng + c(0, 1)
  par(mar = c(7.5, 8.5, 4, 5), family = "sans")
  image(seq_len(ncol(mat)), seq_len(nrow(mat)), t(mat[nrow(mat):1, , drop = FALSE]), col = pal, axes = FALSE, xlab = "", ylab = "", main = "Diet-module-alpha bridge evidence", zlim = rng)
  axis(1, at = seq_len(ncol(mat)), labels = colnames(mat), las = 2, cex.axis = 0.75)
  axis(2, at = seq_len(nrow(mat)), labels = rev(rownames(mat)), las = 1, cex.axis = 0.8)
  abline(v = seq(0.5, ncol(mat) + 0.5, by = 1), col = "white", lwd = 1)
  abline(h = seq(0.5, nrow(mat) + 0.5, by = 1), col = "white", lwd = 1)
  for (i in seq_len(nrow(mat))) {
    for (j in seq_len(ncol(mat))) {
      text(j, i, labels = mat[rev(seq_len(nrow(mat)))[i], j], cex = 0.75, col = "#111111")
    }
  }
  legend_x <- ncol(mat) + 0.65
  legend_y <- seq(0.65, nrow(mat) + 0.35, length.out = length(pal))
  rasterImage(as.raster(matrix(rev(pal), ncol = 1)), legend_x, min(legend_y), legend_x + 0.22, max(legend_y), xpd = NA)
  text(legend_x + 0.35, max(legend_y), sprintf("%.0f", rng[2]), adj = 0, cex = 0.65, xpd = NA)
  text(legend_x + 0.35, min(legend_y), sprintf("%.0f", rng[1]), adj = 0, cex = 0.65, xpd = NA)
  text(legend_x + 0.1, max(legend_y) + 0.35, "bridge count", cex = 0.68, xpd = NA)
}

png_path <- file.path(module_dir, "figures", "figure18_core_module_bridge_heatmap.png")
pdf_path <- file.path(module_dir, "figures", "figure18_core_module_bridge_heatmap.pdf")
png(png_path, width = 1900, height = 1700, res = 300)
plot_bridge()
dev.off()
pdf(pdf_path, width = 1900 / 300, height = 1700 / 300, family = "sans")
plot_bridge()
dev.off()
file.copy(png_path, file.path(central_dir, basename(png_path)), overwrite = TRUE)
file.copy(pdf_path, file.path(central_dir, basename(pdf_path)), overwrite = TRUE)

writeLines(c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "Bridge heatmap generated with complete diet rows.",
  paste0("Rows: ", paste(rownames(mat), collapse = ", ")),
  paste0("Columns: ", paste(colnames(mat), collapse = ", ")),
  paste0("Total bridge count: ", sum(mat, na.rm = TRUE))
), file.path(module_dir, "logs", "module_18_bridge_visualization_summary.txt"), useBytes = TRUE)

message("Module 18 bridge heatmap v2 completed.")
