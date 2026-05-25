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
if (!requireNamespace("writexl", quietly = TRUE)) stop("Missing writexl")

read_csv <- function(path) read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
num <- function(x) suppressWarnings(as.numeric(as.character(x)))
norm_p <- function(beta, se, t_value = NULL) {
  stat <- if (!is.null(t_value)) num(t_value) else num(beta) / num(se)
  out <- 2 * stats::pnorm(-abs(stat))
  out[!is.finite(out)] <- NA_real_
  out
}
fill_p <- function(df) {
  if ("p_value" %in% names(df)) {
    p <- num(df$p_value)
    if ("t" %in% names(df)) {
      p2 <- norm_p(df$beta, df$se, df$t)
    } else {
      p2 <- norm_p(df$beta, df$se)
    }
    p[!is.finite(p)] <- p2[!is.finite(p)]
    df$p_value <- p
  }
  df
}

exposure_order <- c("HEI-2015", "DASH", "aMED", "DII", "E-DII", "hPDI", "uPDI", "PHDI")

da_dir <- file.path(project_root, "15_da_validation_ANCOMBC2_MaAsLin3")
ctype_dir <- file.path(project_root, "16_community_typing")
pca_dir <- file.path(project_root, "17_diet_PCA_patterns")
module_dir <- file.path(project_root, "18_core_module_scores")

package_availability <- read_csv(file.path(da_dir, "processed", "npj_da_validation_package_availability.csv"))
da_cont <- fill_p(read_csv(file.path(da_dir, "processed", "npj_da_validation_maaslin3_style_continuous.csv")))
da_q4 <- fill_p(read_csv(file.path(da_dir, "processed", "npj_da_validation_ancombc2_style_q4_vs_q1.csv")))
da_cont$p_fdr_by_exposure <- ave(da_cont$p_value, da_cont$exposure_label, FUN = function(x) p.adjust(num(x), method = "BH"))
da_q4$p_fdr_by_exposure <- ave(da_q4$p_value, da_q4$exposure_label, FUN = function(x) p.adjust(num(x), method = "BH"))
da_cont$direction <- ifelse(num(da_cont$beta) > 0, "positive", "negative")
da_q4$direction <- ifelse(num(da_q4$beta) > 0, "positive", "negative")
da_validation <- merge(
  da_cont,
  da_q4[, c("exposure_var", "feature_id", "beta", "p_value", "p_fdr_by_exposure", "direction")],
  by = c("exposure_var", "feature_id"),
  suffixes = c("_continuous", "_q4"),
  all.x = TRUE
)
da_validation$validated_direction_consistent <- with(da_validation, !is.na(direction_q4) & direction_continuous == direction_q4)
da_validation$validated_nominal_both <- with(da_validation, validated_direction_consistent & num(p_value_continuous) < 0.05 & num(p_value_q4) < 0.05)
da_validation$validated_fdr_any <- with(da_validation, validated_direction_consistent & (num(p_fdr_by_exposure_continuous) < 0.1 | num(p_fdr_by_exposure_q4) < 0.1))
da_summary <- aggregate(
  cbind(n_nominal_both = da_validation$validated_nominal_both, n_fdr_any = da_validation$validated_fdr_any),
  by = list(exposure_label = da_validation$exposure_label),
  FUN = sum,
  na.rm = TRUE
)
write_csv(da_cont, file.path(da_dir, "processed", "npj_da_validation_maaslin3_style_continuous.csv"))
write_csv(da_q4, file.path(da_dir, "processed", "npj_da_validation_ancombc2_style_q4_vs_q1.csv"))
write_csv(da_validation, file.path(da_dir, "processed", "npj_da_validation_cross_method_consistency.csv"))
write_csv(da_summary, file.path(da_dir, "processed", "npj_da_validation_summary_by_diet.csv"))
writexl::write_xlsx(
  list(
    package_availability = package_availability,
    maaslin3_style_continuous = da_cont,
    ancombc2_style_q4_vs_q1 = da_q4,
    cross_method_consistency = da_validation,
    summary_by_diet = da_summary
  ),
  file.path(da_dir, "processed", "npj_da_validation_ANCOMBC2_MaAsLin3_results.xlsx")
)

ctype_assoc <- fill_p(read_csv(file.path(ctype_dir, "processed", "npj_community_type_diet_associations.csv")))
ctype_assoc$OR <- exp(num(ctype_assoc$beta))
ctype_assoc$OR_low <- exp(num(ctype_assoc$beta) - 1.96 * num(ctype_assoc$se))
ctype_assoc$OR_high <- exp(num(ctype_assoc$beta) + 1.96 * num(ctype_assoc$se))
ctype_assoc$p_fdr_global <- p.adjust(num(ctype_assoc$p_value), method = "BH")
write_csv(ctype_assoc, file.path(ctype_dir, "processed", "npj_community_type_diet_associations.csv"))
writexl::write_xlsx(
  list(
    silhouette = read_csv(file.path(ctype_dir, "processed", "npj_community_type_silhouette_by_k.csv")),
    assignments = read_csv(file.path(ctype_dir, "processed", "npj_community_type_assignments.csv")),
    top_taxa = read_csv(file.path(ctype_dir, "processed", "npj_community_type_top_taxa.csv")),
    diet_associations = ctype_assoc
  ),
  file.path(ctype_dir, "processed", "npj_community_typing_results.xlsx")
)

pca_alpha <- fill_p(read_csv(file.path(pca_dir, "processed", "npj_diet_pca_alpha_associations.csv")))
pca_alpha$p_fdr <- ave(pca_alpha$p_value, pca_alpha$PC, FUN = function(x) p.adjust(num(x), method = "BH"))
write_csv(pca_alpha, file.path(pca_dir, "processed", "npj_diet_pca_alpha_associations.csv"))
writexl::write_xlsx(
  list(
    variance = read_csv(file.path(pca_dir, "processed", "npj_diet_pca_variance.csv")),
    loadings = read_csv(file.path(pca_dir, "processed", "npj_diet_pca_loadings.csv")),
    scores = read_csv(file.path(pca_dir, "processed", "npj_diet_pca_scores.csv")),
    alpha_associations = pca_alpha
  ),
  file.path(pca_dir, "processed", "npj_diet_PCA_patterns_results.xlsx")
)

module_diet <- fill_p(read_csv(file.path(module_dir, "processed", "npj_core_module_diet_associations.csv")))
module_pc <- fill_p(read_csv(file.path(module_dir, "processed", "npj_core_module_diet_pca_associations.csv")))
module_alpha <- fill_p(read_csv(file.path(module_dir, "processed", "npj_core_module_alpha_associations.csv")))
module_diet$p_fdr_global <- p.adjust(num(module_diet$p_value), method = "BH")
module_pc$p_fdr_global <- p.adjust(num(module_pc$p_value), method = "BH")
module_alpha$p_fdr_global <- p.adjust(num(module_alpha$p_value), method = "BH")
bridge <- merge(
  module_diet[num(module_diet$p_value) < 0.05, ],
  module_alpha[num(module_alpha$p_value) < 0.05, ],
  by = c("module_id", "module_score"),
  suffixes = c("_diet", "_alpha")
)
if (nrow(bridge) > 0) bridge$bridge_direction <- ifelse(num(bridge$beta_diet) * num(bridge$beta_alpha) > 0, "same_direction", "opposite_direction")
write_csv(module_diet, file.path(module_dir, "processed", "npj_core_module_diet_associations.csv"))
write_csv(module_pc, file.path(module_dir, "processed", "npj_core_module_diet_pca_associations.csv"))
write_csv(module_alpha, file.path(module_dir, "processed", "npj_core_module_alpha_associations.csv"))
write_csv(bridge, file.path(module_dir, "processed", "npj_core_module_bridge_diet_alpha.csv"))
module_taxa <- read_csv(file.path(module_dir, "processed", "npj_core_module_taxa_reference.csv"))
writexl::write_xlsx(
  list(
    module_diet = module_diet,
    module_diet_pca = module_pc,
    module_alpha = module_alpha,
    diet_alpha_bridge = bridge,
    module_taxa_reference = module_taxa
  ),
  file.path(module_dir, "processed", "npj_core_module_score_results.xlsx")
)

sil <- read_csv(file.path(ctype_dir, "processed", "npj_community_type_silhouette_by_k.csv"))
var <- read_csv(file.path(pca_dir, "processed", "npj_diet_pca_variance.csv"))
writeLines(c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "Modules completed and p-values refreshed with normal approximation when survey df-based p-values were unavailable.",
  paste0("Community type best k: ", sil$k[which.max(num(sil$avg_silhouette))], "; average silhouette: ", sprintf("%.3f", max(num(sil$avg_silhouette)))),
  paste0("Diet PCA PC1 variance: ", sprintf("%.1f%%", num(var$variance_explained[1]) * 100), "; PC2 variance: ", sprintf("%.1f%%", num(var$variance_explained[2]) * 100)),
  paste0("DA validated nominal both-method signals: ", sum(da_validation$validated_nominal_both, na.rm = TRUE)),
  paste0("Module-diet nominal associations: ", sum(num(module_diet$p_value) < 0.05, na.rm = TRUE)),
  paste0("Module-alpha nominal associations: ", sum(num(module_alpha$p_value) < 0.05, na.rm = TRUE)),
  paste0("Module bridge rows: ", nrow(bridge))
), file.path(project_root, "00_protocol_and_log", "npj_15_18_supplementary_modules_summary.txt"), useBytes = TRUE)

writeLines(c(
  "DA validation summary",
  paste0("Validated nominal both-method signals: ", sum(da_validation$validated_nominal_both, na.rm = TRUE)),
  paste0("Validated FDR-level signals: ", sum(da_validation$validated_fdr_any, na.rm = TRUE))
), file.path(da_dir, "logs", "module_15_da_validation_summary.txt"), useBytes = TRUE)
writeLines(c(
  "Core module score summary",
  paste0("Module-diet nominal associations: ", sum(num(module_diet$p_value) < 0.05, na.rm = TRUE)),
  paste0("Module-alpha nominal associations: ", sum(num(module_alpha$p_value) < 0.05, na.rm = TRUE)),
  paste0("Diet-alpha bridge rows: ", nrow(bridge))
), file.path(module_dir, "logs", "module_18_core_module_summary.txt"), useBytes = TRUE)

message("P-values, ORs, FDRs, and bridge tables refreshed.")
