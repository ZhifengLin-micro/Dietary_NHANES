options(stringsAsFactors = FALSE)

args_full <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = TRUE)
  project_root <- dirname(script_path)
} else {
  project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
}
workspace_root <- normalizePath(file.path(project_root, ".."), winslash = "/", mustWork = TRUE)
project_lib <- file.path(workspace_root, ".Rlib")
if (dir.exists(project_lib)) .libPaths(c(project_lib, .libPaths()))

required_pkgs <- c("data.table", "survey", "vegan", "cluster", "writexl")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))

suppressPackageStartupMessages({
  library(data.table)
  library(survey)
  library(vegan)
  library(cluster)
  library(writexl)
})

options(survey.lonely.psu = "adjust")
set.seed(20260512)

dirs <- list(
  da = file.path(project_root, "15_da_validation_ANCOMBC2_MaAsLin3"),
  ctype = file.path(project_root, "16_community_typing"),
  pca = file.path(project_root, "17_diet_PCA_patterns"),
  module = file.path(project_root, "18_core_module_scores")
)
for (d in dirs) {
  dir.create(file.path(d, "processed"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "logs"), recursive = TRUE, showWarnings = FALSE)
}

metadata_path <- file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_analysis_metadata.rds")
rel_path <- file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_relative_filtered_matrix.rds")
clr_path <- file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_clr_filtered_matrix.rds")
feature_index_path <- file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_feature_index.csv")
module_score_path <- file.path(project_root, "08_ecological_modules_and_network", "processed", "npj_ecological_module_eigengene_scores.csv")
module_taxa_path <- file.path(project_root, "08_ecological_modules_and_network", "processed", "npj_ecological_module_taxa_table.csv")
stopifnot(file.exists(metadata_path), file.exists(rel_path), file.exists(clr_path), file.exists(feature_index_path))

metadata <- readRDS(metadata_path)
relative_mat <- readRDS(rel_path)
clr_mat <- readRDS(clr_path)
feature_index <- read.csv(feature_index_path, check.names = FALSE)
metadata$SEQN <- as.character(metadata$SEQN)
relative_mat$SEQN <- as.character(relative_mat$SEQN)
clr_mat$SEQN <- as.character(clr_mat$SEQN)
feature_index$feature_id <- as.character(feature_index$feature_id)
module_scores <- if (file.exists(module_score_path)) read.csv(module_score_path, check.names = FALSE) else data.frame()
module_taxa <- if (file.exists(module_taxa_path)) read.csv(module_taxa_path, check.names = FALSE) else data.frame()
if (nrow(module_scores) > 0) module_scores$SEQN <- as.character(module_scores$SEQN)

exposure_map <- c(
  HEI2015_ALL = "HEI-2015",
  DASH_ALL = "DASH",
  MED_ALL = "aMED",
  DII_STANDARD_28 = "DII",
  E_DII_RESIDUAL_27 = "E-DII",
  hPDI_MPED16 = "hPDI",
  uPDI_MPED16 = "uPDI",
  PHDI_ALL = "PHDI"
)
exposure_vars <- names(exposure_map)
exposure_z <- paste0(exposure_vars, "_z")
exposure_q4 <- paste0(exposure_vars, "_q4")
exposure_labels <- unname(exposure_map)

model_covariates <- c(
  "age_years", "sex", "race_ethnicity", "education", "marital", "pir",
  "smoking", "alcohol_12plus", "bmi", "total_energy_kcal", "diabetes",
  "hypertension", "teeth_present_n", "periodontal_status_proxy", "edentulous",
  "recent_dental_visit", "preventive_dental_visit", "rx_use_any"
)
design_vars <- c("SDMVPSU", "SDMVSTRA", "WTDR2D_4YR")
alpha_vars <- c("observed_asv", "faith_pd", "shannon_index", "inverse_simpson_index")

write_csv_utf8 <- function(x, path) write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
fmt_p <- function(p) ifelse(is.na(p), NA_character_, ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))

clean_factor_vars <- function(df) {
  for (v in names(df)) {
    if (is.character(df[[v]]) && !v %in% "SEQN") df[[v]] <- factor(df[[v]])
  }
  df
}

make_design <- function(df) {
  df <- clean_factor_vars(df)
  survey::svydesign(
    ids = stats::as.formula("~SDMVPSU"),
    strata = stats::as.formula("~SDMVSTRA"),
    weights = stats::as.formula("~WTDR2D_4YR"),
    nest = TRUE,
    data = df
  )
}

extract_svy_term <- function(fit, term_regex) {
  sm <- tryCatch(as.data.frame(summary(fit)$coefficients), error = function(e) data.frame())
  if (nrow(sm) == 0) return(c(beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_))
  hit <- grep(term_regex, rownames(sm), value = TRUE)
  if (length(hit) == 0) return(c(beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_))
  row <- sm[hit[1], , drop = FALSE]
  p_col <- grep("Pr", names(row), value = TRUE)[1]
  c(beta = as.numeric(row[[1]][1]), se = as.numeric(row[[2]][1]), t = as.numeric(row[[3]][1]), p = if (!is.na(p_col)) as.numeric(row[[p_col]][1]) else NA_real_)
}

run_svy_lm <- function(df, outcome, exposure, covariates = model_covariates, term_regex = NULL) {
  needed <- unique(c("SEQN", design_vars, outcome, exposure, covariates))
  sub <- df[, needed[needed %in% names(df)], drop = FALSE]
  sub <- sub[stats::complete.cases(sub), , drop = FALSE]
  if (nrow(sub) < 100) return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_))
  des <- make_design(sub)
  form <- stats::as.formula(paste(outcome, "~", paste(c(exposure, covariates), collapse = " + ")))
  fit <- tryCatch(survey::svyglm(form, design = des), error = function(e) e)
  if (inherits(fit, "error")) return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_))
  c(n = nrow(sub), extract_svy_term(fit, if (is.null(term_regex)) paste0("^", exposure, "$") else term_regex))
}

run_svy_logistic <- function(df, outcome, exposure, covariates = model_covariates, term_regex = NULL) {
  needed <- unique(c("SEQN", design_vars, outcome, exposure, covariates))
  sub <- df[, needed[needed %in% names(df)], drop = FALSE]
  sub <- sub[stats::complete.cases(sub), , drop = FALSE]
  if (nrow(sub) < 100 || length(unique(sub[[outcome]])) < 2) {
    return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_, OR = NA_real_, OR_low = NA_real_, OR_high = NA_real_))
  }
  des <- make_design(sub)
  form <- stats::as.formula(paste(outcome, "~", paste(c(exposure, covariates), collapse = " + ")))
  fit <- tryCatch(survey::svyglm(form, design = des, family = quasibinomial()), error = function(e) e)
  if (inherits(fit, "error")) {
    return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_, OR = NA_real_, OR_low = NA_real_, OR_high = NA_real_))
  }
  out <- extract_svy_term(fit, if (is.null(term_regex)) paste0("^", exposure, "$") else term_regex)
  beta <- out["beta"]
  se <- out["se"]
  c(n = nrow(sub), out, OR = exp(beta), OR_low = exp(beta - 1.96 * se), OR_high = exp(beta + 1.96 * se))
}

merge_metadata_matrix <- function(mat, flag_var) {
  ids <- intersect(metadata$SEQN, mat$SEQN)
  md <- metadata[match(ids, metadata$SEQN), , drop = FALSE]
  mx <- mat[match(ids, mat$SEQN), , drop = FALSE]
  df <- cbind(md, mx[, setdiff(names(mx), "SEQN"), drop = FALSE])
  if (flag_var %in% names(df)) df <- df[df[[flag_var]] %in% TRUE, , drop = FALSE]
  df
}

plot_heatmap_base <- function(mat, path, title, zlab = "value", digits = 2, width = 2600, height = 1900) {
  mat <- as.matrix(mat)
  rng <- range(mat, na.rm = TRUE)
  if (!all(is.finite(rng))) rng <- c(-1, 1)
  if (diff(rng) == 0) rng <- rng + c(-1e-6, 1e-6)
  pal <- grDevices::colorRampPalette(c("#3B4CC0", "#D8ECF3", "#F6E8C3", "#F4A261", "#B2182B"))(101)
  png(path, width = width, height = height, res = 300)
  par(mar = c(7.5, 10, 4, 5), family = "sans")
  image(seq_len(ncol(mat)), seq_len(nrow(mat)), t(mat[nrow(mat):1, , drop = FALSE]), col = pal, axes = FALSE, xlab = "", ylab = "", main = title, zlim = rng)
  axis(1, at = seq_len(ncol(mat)), labels = colnames(mat), las = 2, cex.axis = 0.72)
  axis(2, at = seq_len(nrow(mat)), labels = rev(rownames(mat)), las = 1, cex.axis = 0.72)
  abline(v = seq(0.5, ncol(mat) + 0.5, by = 1), col = "white", lwd = 0.8)
  abline(h = seq(0.5, nrow(mat) + 0.5, by = 1), col = "white", lwd = 0.8)
  if (nrow(mat) <= 35 && ncol(mat) <= 12) {
    for (i in seq_len(nrow(mat))) {
      for (j in seq_len(ncol(mat))) {
        val <- mat[rev(seq_len(nrow(mat)))[i], j]
        if (!is.na(val)) text(j, i, sprintf(paste0("%.", digits, "f"), val), cex = 0.45, col = "#111111")
      }
    }
  }
  legend_x <- ncol(mat) + 0.65
  legend_y <- seq(0.6, nrow(mat) + 0.4, length.out = length(pal))
  rasterImage(as.raster(matrix(rev(pal), ncol = 1)), legend_x, min(legend_y), legend_x + 0.22, max(legend_y), xpd = NA)
  text(legend_x + 0.35, max(legend_y), sprintf("%.2f", rng[2]), adj = 0, cex = 0.6, xpd = NA)
  text(legend_x + 0.35, min(legend_y), sprintf("%.2f", rng[1]), adj = 0, cex = 0.6, xpd = NA)
  text(legend_x + 0.1, max(legend_y) + 0.35, zlab, cex = 0.65, xpd = NA)
  dev.off()
}

package_availability <- data.frame(
  package = c("ANCOMBC", "Maaslin2", "Maaslin3"),
  available = vapply(c("ANCOMBC", "Maaslin2", "Maaslin3"), requireNamespace, quietly = TRUE, FUN.VALUE = logical(1)),
  stringsAsFactors = FALSE
)

message("Module 15: differential abundance validation")
da_dir <- dirs$da
write_csv_utf8(package_availability, file.path(da_dir, "processed", "npj_da_validation_package_availability.csv"))
da_df <- merge_metadata_matrix(clr_mat, "analysis_genus_model3_all_exposures")
clr_cols <- setdiff(names(clr_mat), "SEQN")
feature_ids <- sub("__clr$", "", clr_cols)
feature_labels <- feature_index$tax_label[match(feature_ids, feature_index$feature_id)]
feature_labels[is.na(feature_labels) | feature_labels == ""] <- feature_ids[is.na(feature_labels) | feature_labels == ""]
names(feature_labels) <- clr_cols
continuous_results <- list()
quartile_results <- list()
for (exp_var in exposure_vars) {
  exp_z <- paste0(exp_var, "_z")
  qvar <- paste0(exp_var, "_q4")
  da_df[[qvar]] <- stats::relevel(factor(as.character(da_df[[qvar]]), levels = paste0("Q", 1:4)), ref = "Q1")
  for (tax_col in clr_cols) {
    cont <- run_svy_lm(da_df, tax_col, exp_z)
    continuous_results[[length(continuous_results) + 1]] <- data.frame(
      method_layer = "MaAsLin3_style_survey_CLR_continuous",
      exposure_var = exp_var,
      exposure_label = exposure_map[[exp_var]],
      feature_id = sub("__clr$", "", tax_col),
      tax_label = feature_labels[[tax_col]],
      n = cont["n"], beta = cont["beta"], se = cont["se"], t = cont["t"], p_value = cont["p"],
      stringsAsFactors = FALSE
    )
    q4 <- run_svy_lm(da_df, tax_col, qvar, term_regex = paste0("^", qvar, "Q4$"))
    quartile_results[[length(quartile_results) + 1]] <- data.frame(
      method_layer = "ANCOMBC2_style_survey_CLR_Q4_vs_Q1",
      exposure_var = exp_var,
      exposure_label = exposure_map[[exp_var]],
      feature_id = sub("__clr$", "", tax_col),
      tax_label = feature_labels[[tax_col]],
      contrast = "Q4_vs_Q1",
      n = q4["n"], beta = q4["beta"], se = q4["se"], t = q4["t"], p_value = q4["p"],
      stringsAsFactors = FALSE
    )
  }
}
da_cont <- data.table::rbindlist(continuous_results, fill = TRUE)
da_q4 <- data.table::rbindlist(quartile_results, fill = TRUE)
da_cont$p_fdr_by_exposure <- ave(da_cont$p_value, da_cont$exposure_label, FUN = function(x) p.adjust(x, method = "BH"))
da_q4$p_fdr_by_exposure <- ave(da_q4$p_value, da_q4$exposure_label, FUN = function(x) p.adjust(x, method = "BH"))
da_cont$direction <- ifelse(da_cont$beta > 0, "positive", "negative")
da_q4$direction <- ifelse(da_q4$beta > 0, "positive", "negative")
da_validation <- merge(
  da_cont,
  da_q4[, c("exposure_var", "feature_id", "beta", "p_value", "p_fdr_by_exposure", "direction")],
  by = c("exposure_var", "feature_id"),
  suffixes = c("_continuous", "_q4"),
  all.x = TRUE
)
da_validation$validated_direction_consistent <- with(da_validation, !is.na(direction_q4) & direction_continuous == direction_q4)
da_validation$validated_nominal_both <- with(da_validation, validated_direction_consistent & p_value_continuous < 0.05 & p_value_q4 < 0.05)
da_validation$validated_fdr_any <- with(da_validation, validated_direction_consistent & (p_fdr_by_exposure_continuous < 0.1 | p_fdr_by_exposure_q4 < 0.1))
da_summary <- aggregate(cbind(n_nominal_both = da_validation$validated_nominal_both, n_fdr_any = da_validation$validated_fdr_any), by = list(exposure_label = da_validation$exposure_label), FUN = sum, na.rm = TRUE)
top_da <- da_validation[order(!da_validation$validated_nominal_both, da_validation$p_value_continuous, -abs(da_validation$beta_continuous)), ]
top_da <- top_da[seq_len(min(80, nrow(top_da))), ]
write_csv_utf8(da_cont, file.path(da_dir, "processed", "npj_da_validation_maaslin3_style_continuous.csv"))
write_csv_utf8(da_q4, file.path(da_dir, "processed", "npj_da_validation_ancombc2_style_q4_vs_q1.csv"))
write_csv_utf8(da_validation, file.path(da_dir, "processed", "npj_da_validation_cross_method_consistency.csv"))
write_csv_utf8(da_summary, file.path(da_dir, "processed", "npj_da_validation_summary_by_diet.csv"))
writexl::write_xlsx(list(package_availability = package_availability, maaslin3_style_continuous = as.data.frame(da_cont), ancombc2_style_q4_vs_q1 = as.data.frame(da_q4), cross_method_consistency = as.data.frame(da_validation), summary_by_diet = as.data.frame(da_summary)), file.path(da_dir, "processed", "npj_da_validation_ANCOMBC2_MaAsLin3_results.xlsx"))
heat_features <- unique(top_da$tax_label)[seq_len(min(30, length(unique(top_da$tax_label))))]
heat_mat <- matrix(NA_real_, nrow = length(heat_features), ncol = length(exposure_labels), dimnames = list(heat_features, exposure_labels))
for (i in seq_len(nrow(da_cont))) if (da_cont$tax_label[i] %in% heat_features) heat_mat[da_cont$tax_label[i], da_cont$exposure_label[i]] <- da_cont$beta[i]
plot_heatmap_base(heat_mat, file.path(da_dir, "figures", "figure_da_validation_beta_heatmap.png"), "Differential abundance validation: survey-weighted CLR beta", "beta", 2)

message("Module 16: community typing")
ctype_dir <- dirs$ctype
ctype_df <- merge_metadata_matrix(relative_mat, "analysis_beta_model3_all_exposures")
rel_cols <- setdiff(names(relative_mat), "SEQN")
needed_ctype <- unique(c("SEQN", design_vars, exposure_z, model_covariates, rel_cols))
ctype_df <- ctype_df[stats::complete.cases(ctype_df[, needed_ctype]), needed_ctype, drop = FALSE]
rel_matrix <- as.matrix(ctype_df[, rel_cols, drop = FALSE])
storage.mode(rel_matrix) <- "numeric"
rel_matrix[is.na(rel_matrix)] <- 0
hellinger <- sqrt(rel_matrix)
bray_dist <- vegan::vegdist(hellinger, method = "bray")
k_values <- 2:6
pam_objects <- list()
silhouette_df <- data.frame()
for (k in k_values) {
  pam_fit <- cluster::pam(bray_dist, k = k, diss = TRUE)
  pam_objects[[as.character(k)]] <- pam_fit
  silhouette_df <- rbind(silhouette_df, data.frame(k = k, avg_silhouette = pam_fit$silinfo$avg.width, stringsAsFactors = FALSE))
}
best_k <- silhouette_df$k[which.max(silhouette_df$avg_silhouette)]
best_pam <- pam_objects[[as.character(best_k)]]
ctype_assign <- data.frame(SEQN = ctype_df$SEQN, community_type = paste0("CT", best_pam$clustering), silhouette_width = best_pam$silinfo$widths[, "sil_width"], stringsAsFactors = FALSE)
ctype_assign$community_type <- factor(ctype_assign$community_type, levels = paste0("CT", seq_len(best_k)))
ctype_join <- merge(ctype_df[, c("SEQN", design_vars, exposure_z, model_covariates), drop = FALSE], ctype_assign, by = "SEQN")
centroids <- aggregate(rel_matrix, by = list(community_type = ctype_assign$community_type), FUN = mean)
cent_long <- data.table::melt(data.table::as.data.table(centroids), id.vars = "community_type", variable.name = "feature_id", value.name = "mean_relative_abundance")
cent_long$tax_label <- feature_index$tax_label[match(cent_long$feature_id, feature_index$feature_id)]
cent_long$tax_label[is.na(cent_long$tax_label)] <- as.character(cent_long$feature_id[is.na(cent_long$tax_label)])
cent_long <- cent_long[order(cent_long$community_type, -cent_long$mean_relative_abundance), ]
top_centroids <- cent_long[, head(.SD, 12), by = community_type]
ref_type <- names(which.max(table(ctype_assign$community_type)))
ctype_assoc <- list()
for (target in setdiff(levels(ctype_assign$community_type), ref_type)) {
  pair <- ctype_join[ctype_join$community_type %in% c(ref_type, target), , drop = FALSE]
  pair$target_type <- as.integer(pair$community_type == target)
  for (ez in exposure_z) {
    lg <- run_svy_logistic(pair, "target_type", ez)
    ctype_assoc[[length(ctype_assoc) + 1]] <- data.frame(reference_type = ref_type, target_type = target, exposure_var = sub("_z$", "", ez), exposure_label = exposure_map[[sub("_z$", "", ez)]], n = lg["n"], beta = lg["beta"], se = lg["se"], p_value = lg["p"], OR = lg["OR"], OR_low = lg["OR_low"], OR_high = lg["OR_high"], stringsAsFactors = FALSE)
  }
}
ctype_assoc <- data.table::rbindlist(ctype_assoc, fill = TRUE)
ctype_assoc$p_fdr_global <- p.adjust(ctype_assoc$p_value, method = "BH")
write_csv_utf8(silhouette_df, file.path(ctype_dir, "processed", "npj_community_type_silhouette_by_k.csv"))
write_csv_utf8(ctype_assign, file.path(ctype_dir, "processed", "npj_community_type_assignments.csv"))
write_csv_utf8(cent_long, file.path(ctype_dir, "processed", "npj_community_type_taxa_centroids_long.csv"))
write_csv_utf8(top_centroids, file.path(ctype_dir, "processed", "npj_community_type_top_taxa.csv"))
write_csv_utf8(ctype_assoc, file.path(ctype_dir, "processed", "npj_community_type_diet_associations.csv"))
writexl::write_xlsx(list(silhouette = silhouette_df, assignments = ctype_assign, top_taxa = as.data.frame(top_centroids), diet_associations = as.data.frame(ctype_assoc)), file.path(ctype_dir, "processed", "npj_community_typing_results.xlsx"))
png(file.path(ctype_dir, "figures", "figure_community_type_silhouette.png"), width = 1800, height = 1300, res = 300)
par(mar = c(5, 5, 3, 1), family = "sans")
plot(silhouette_df$k, silhouette_df$avg_silhouette, type = "b", pch = 19, lwd = 2, col = "#2A6F97", xlab = "Number of community types", ylab = "Average silhouette width", main = "Community typing model selection")
abline(v = best_k, col = "#B2182B", lty = 2)
dev.off()
top_taxa_overall <- names(sort(colMeans(rel_matrix), decreasing = TRUE))[seq_len(min(18, ncol(rel_matrix)))]
ctype_heat <- as.matrix(centroids[, top_taxa_overall, drop = FALSE])
rownames(ctype_heat) <- centroids$community_type
colnames(ctype_heat) <- feature_index$tax_label[match(top_taxa_overall, feature_index$feature_id)]
plot_heatmap_base(log10(ctype_heat + 1e-6), file.path(ctype_dir, "figures", "figure_community_type_top_taxa_heatmap.png"), "Community type taxonomic signatures", "log10 abundance", 2, 2600, 1600)

message("Module 17: diet PCA patterns")
pca_dir <- dirs$pca
pca_needed <- unique(c("SEQN", design_vars, exposure_z, exposure_q4, model_covariates, alpha_vars))
pca_df <- metadata[metadata$analysis_alpha_model3_all_exposures %in% TRUE, pca_needed, drop = FALSE]
pca_df <- pca_df[stats::complete.cases(pca_df[, unique(c("SEQN", design_vars, exposure_z, model_covariates))]), , drop = FALSE]
diet_mat <- as.matrix(pca_df[, exposure_z, drop = FALSE])
storage.mode(diet_mat) <- "numeric"
pca_fit <- stats::prcomp(diet_mat, center = TRUE, scale. = FALSE)
loadings <- pca_fit$rotation
scores <- pca_fit$x
healthy_vars <- paste0(c("HEI2015_ALL", "DASH_ALL", "MED_ALL", "hPDI_MPED16", "PHDI_ALL"), "_z")
unhealthy_vars <- paste0(c("DII_STANDARD_28", "uPDI_MPED16"), "_z")
if (mean(loadings[healthy_vars, 1], na.rm = TRUE) < mean(loadings[unhealthy_vars, 1], na.rm = TRUE)) {
  loadings[, 1] <- -loadings[, 1]
  scores[, 1] <- -scores[, 1]
}
if ("uPDI_MPED16_z" %in% rownames(loadings) && loadings["uPDI_MPED16_z", 2] < 0) {
  loadings[, 2] <- -loadings[, 2]
  scores[, 2] <- -scores[, 2]
}
variance_df <- data.frame(PC = paste0("PC", seq_along(pca_fit$sdev)), eigenvalue = pca_fit$sdev^2, variance_explained = pca_fit$sdev^2 / sum(pca_fit$sdev^2), cumulative_variance = cumsum(pca_fit$sdev^2 / sum(pca_fit$sdev^2)), stringsAsFactors = FALSE)
loading_df <- data.frame(diet_index = exposure_labels, variable = exposure_z, loadings[, seq_len(min(4, ncol(loadings))), drop = FALSE], check.names = FALSE)
score_df <- data.frame(SEQN = pca_df$SEQN, scores[, seq_len(min(4, ncol(scores))), drop = FALSE], check.names = FALSE)
pca_model_df <- merge(pca_df, score_df, by = "SEQN")
pca_alpha <- list()
for (pc in c("PC1", "PC2")) {
  for (alpha in alpha_vars) {
    fit <- run_svy_lm(pca_model_df, alpha, pc)
    pca_alpha[[length(pca_alpha) + 1]] <- data.frame(PC = pc, outcome = alpha, n = fit["n"], beta = fit["beta"], se = fit["se"], p_value = fit["p"], stringsAsFactors = FALSE)
  }
}
pca_alpha <- data.table::rbindlist(pca_alpha, fill = TRUE)
pca_alpha$p_fdr <- ave(pca_alpha$p_value, pca_alpha$PC, FUN = function(x) p.adjust(x, method = "BH"))
write_csv_utf8(variance_df, file.path(pca_dir, "processed", "npj_diet_pca_variance.csv"))
write_csv_utf8(loading_df, file.path(pca_dir, "processed", "npj_diet_pca_loadings.csv"))
write_csv_utf8(score_df, file.path(pca_dir, "processed", "npj_diet_pca_scores.csv"))
write_csv_utf8(pca_alpha, file.path(pca_dir, "processed", "npj_diet_pca_alpha_associations.csv"))
writexl::write_xlsx(list(variance = variance_df, loadings = loading_df, scores = score_df, alpha_associations = as.data.frame(pca_alpha)), file.path(pca_dir, "processed", "npj_diet_PCA_patterns_results.xlsx"))
load_mat <- as.matrix(loading_df[, c("PC1", "PC2", "PC3"), drop = FALSE])
rownames(load_mat) <- loading_df$diet_index
plot_heatmap_base(load_mat, file.path(pca_dir, "figures", "figure_diet_pca_loadings_heatmap.png"), "Diet index PCA loadings", "loading", 2, 2100, 1700)
png(file.path(pca_dir, "figures", "figure_diet_pca_scree.png"), width = 1800, height = 1300, res = 300)
par(mar = c(5, 5, 3, 1), family = "sans")
barplot(variance_df$variance_explained[1:8] * 100, names.arg = variance_df$PC[1:8], col = "#74A9CF", border = NA, ylab = "Variance explained (%)", main = "Diet PCA scree plot")
lines(seq_len(8), variance_df$cumulative_variance[1:8] * 100, type = "b", pch = 19, col = "#B2182B")
dev.off()
alpha_mat <- matrix(NA_real_, nrow = length(alpha_vars), ncol = 2, dimnames = list(alpha_vars, c("PC1", "PC2")))
for (i in seq_len(nrow(pca_alpha))) alpha_mat[pca_alpha$outcome[i], pca_alpha$PC[i]] <- pca_alpha$beta[i]
plot_heatmap_base(alpha_mat, file.path(pca_dir, "figures", "figure_diet_pca_alpha_heatmap.png"), "Diet PCA associations with alpha diversity", "beta", 2, 1800, 1500)

message("Module 18: core module score analysis")
module_dir <- dirs$module
if (nrow(module_scores) == 0) stop("Module score file is missing.")
module_cols <- grep("^ME_M", names(module_scores), value = TRUE)
module_df <- merge(metadata, module_scores, by = "SEQN")
module_df <- module_df[module_df$analysis_alpha_model3_all_exposures %in% TRUE, , drop = FALSE]
module_diet <- list()
for (mod in module_cols) {
  for (ez in exposure_z) {
    fit <- run_svy_lm(module_df, mod, ez)
    module_diet[[length(module_diet) + 1]] <- data.frame(module_id = sub("^ME_", "", mod), module_score = mod, exposure_var = sub("_z$", "", ez), exposure_label = exposure_map[[sub("_z$", "", ez)]], n = fit["n"], beta = fit["beta"], se = fit["se"], p_value = fit["p"], stringsAsFactors = FALSE)
  }
}
module_diet <- data.table::rbindlist(module_diet, fill = TRUE)
module_diet$p_fdr_global <- p.adjust(module_diet$p_value, method = "BH")
module_pca <- merge(module_df, score_df[, c("SEQN", "PC1", "PC2"), drop = FALSE], by = "SEQN")
module_pc_assoc <- list()
for (mod in module_cols) {
  for (pc in c("PC1", "PC2")) {
    fit <- run_svy_lm(module_pca, mod, pc)
    module_pc_assoc[[length(module_pc_assoc) + 1]] <- data.frame(module_id = sub("^ME_", "", mod), module_score = mod, PC = pc, n = fit["n"], beta = fit["beta"], se = fit["se"], p_value = fit["p"], stringsAsFactors = FALSE)
  }
}
module_pc_assoc <- data.table::rbindlist(module_pc_assoc, fill = TRUE)
module_pc_assoc$p_fdr_global <- p.adjust(module_pc_assoc$p_value, method = "BH")
module_alpha <- list()
for (alpha in alpha_vars) {
  for (mod in module_cols) {
    fit <- run_svy_lm(module_df, alpha, mod)
    module_alpha[[length(module_alpha) + 1]] <- data.frame(module_id = sub("^ME_", "", mod), module_score = mod, outcome = alpha, n = fit["n"], beta = fit["beta"], se = fit["se"], p_value = fit["p"], stringsAsFactors = FALSE)
  }
}
module_alpha <- data.table::rbindlist(module_alpha, fill = TRUE)
module_alpha$p_fdr_global <- p.adjust(module_alpha$p_value, method = "BH")
bridge <- merge(module_diet[module_diet$p_value < 0.05, ], module_alpha[module_alpha$p_value < 0.05, ], by = c("module_id", "module_score"), suffixes = c("_diet", "_alpha"))
bridge$bridge_direction <- ifelse(bridge$beta_diet * bridge$beta_alpha > 0, "same_direction", "opposite_direction")
write_csv_utf8(module_diet, file.path(module_dir, "processed", "npj_core_module_diet_associations.csv"))
write_csv_utf8(module_pc_assoc, file.path(module_dir, "processed", "npj_core_module_diet_pca_associations.csv"))
write_csv_utf8(module_alpha, file.path(module_dir, "processed", "npj_core_module_alpha_associations.csv"))
write_csv_utf8(bridge, file.path(module_dir, "processed", "npj_core_module_bridge_diet_alpha.csv"))
if (nrow(module_taxa) > 0) write_csv_utf8(module_taxa, file.path(module_dir, "processed", "npj_core_module_taxa_reference.csv"))
writexl::write_xlsx(list(module_diet = as.data.frame(module_diet), module_diet_pca = as.data.frame(module_pc_assoc), module_alpha = as.data.frame(module_alpha), diet_alpha_bridge = as.data.frame(bridge), module_taxa_reference = as.data.frame(module_taxa)), file.path(module_dir, "processed", "npj_core_module_score_results.xlsx"))
module_heat <- matrix(NA_real_, nrow = length(module_cols), ncol = length(exposure_labels), dimnames = list(sub("^ME_", "", module_cols), exposure_labels))
for (i in seq_len(nrow(module_diet))) module_heat[module_diet$module_id[i], module_diet$exposure_label[i]] <- module_diet$beta[i]
plot_heatmap_base(module_heat, file.path(module_dir, "figures", "figure_core_module_diet_heatmap.png"), "Core ecological module scores and diet indices", "beta", 2, 2200, 1700)
alpha_heat <- matrix(NA_real_, nrow = length(module_cols), ncol = length(alpha_vars), dimnames = list(sub("^ME_", "", module_cols), alpha_vars))
for (i in seq_len(nrow(module_alpha))) alpha_heat[module_alpha$module_id[i], module_alpha$outcome[i]] <- module_alpha$beta[i]
plot_heatmap_base(alpha_heat, file.path(module_dir, "figures", "figure_core_module_alpha_heatmap.png"), "Core ecological module scores and alpha diversity", "beta", 2, 1900, 1700)

writeLines(c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "Modules completed: 15 DA validation, 16 community typing, 17 diet PCA, 18 core module scores.",
  paste0("ANCOMBC available: ", package_availability$available[package_availability$package == "ANCOMBC"]),
  paste0("Maaslin3 available: ", package_availability$available[package_availability$package == "Maaslin3"]),
  "When standard packages were unavailable, survey-weighted CLR validation layers were used.",
  paste0("Community type best k: ", best_k, "; average silhouette: ", sprintf("%.3f", max(silhouette_df$avg_silhouette))),
  paste0("Diet PCA PC1 variance: ", sprintf("%.1f%%", variance_df$variance_explained[1] * 100), "; PC2 variance: ", sprintf("%.1f%%", variance_df$variance_explained[2] * 100)),
  paste0("Module-diet nominal associations: ", sum(module_diet$p_value < 0.05, na.rm = TRUE)),
  paste0("Module-alpha nominal associations: ", sum(module_alpha$p_value < 0.05, na.rm = TRUE))
), file.path(project_root, "00_protocol_and_log", "npj_15_18_supplementary_modules_summary.txt"), useBytes = TRUE)
writeLines(c("DA validation summary", paste0("Validated nominal both-method signals: ", sum(da_validation$validated_nominal_both, na.rm = TRUE)), paste0("Validated FDR-level signals: ", sum(da_validation$validated_fdr_any, na.rm = TRUE))), file.path(da_dir, "logs", "module_15_da_validation_summary.txt"), useBytes = TRUE)
writeLines(c("Community typing summary", paste0("Best k: ", best_k), paste0("Average silhouette: ", sprintf("%.3f", max(silhouette_df$avg_silhouette))), paste0("Reference type for diet association: ", ref_type)), file.path(ctype_dir, "logs", "module_16_community_typing_summary.txt"), useBytes = TRUE)
writeLines(c("Diet PCA summary", paste0("PC1 variance: ", sprintf("%.1f%%", variance_df$variance_explained[1] * 100)), paste0("PC2 variance: ", sprintf("%.1f%%", variance_df$variance_explained[2] * 100))), file.path(pca_dir, "logs", "module_17_diet_pca_summary.txt"), useBytes = TRUE)
writeLines(c("Core module score summary", paste0("Modules: ", paste(sub("^ME_", "", module_cols), collapse = ", ")), paste0("Module-diet nominal associations: ", sum(module_diet$p_value < 0.05, na.rm = TRUE)), paste0("Module-alpha nominal associations: ", sum(module_alpha$p_value < 0.05, na.rm = TRUE)), paste0("Diet-alpha bridge rows: ", nrow(bridge))), file.path(module_dir, "logs", "module_18_core_module_summary.txt"), useBytes = TRUE)

message("Supplementary modules 15-18 completed.")
