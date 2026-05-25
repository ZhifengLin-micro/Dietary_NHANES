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

required_pkgs <- c("data.table", "survey", "vegan", "splines", "writexl", "haven")
missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
if (length(missing_pkgs) > 0) stop("Missing packages: ", paste(missing_pkgs, collapse = ", "))
suppressPackageStartupMessages({
  library(data.table)
  library(survey)
  library(vegan)
  library(splines)
  library(writexl)
  library(haven)
})
options(survey.lonely.psu = "adjust")
set.seed(20260512)

dirs <- list(
  oral = file.path(project_root, "19_oral_health_outcomes_mediation"),
  dose = file.path(project_root, "20_key_taxa_dose_response"),
  func = file.path(project_root, "21_functional_prediction_feasibility"),
  sens = file.path(project_root, "22_medication_dental_sensitivity"),
  wu = file.path(project_root, "23_weighted_unweighted_comparison"),
  central = file.path(project_root, "12_figures_tables_npj", "figures_19_23_extension")
)
for (d in dirs) {
  dir.create(file.path(d, "processed"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "logs"), recursive = TRUE, showWarnings = FALSE)
}
dir.create(dirs$central, recursive = TRUE, showWarnings = FALSE)

metadata <- readRDS(file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_analysis_metadata.rds"))
clr_mat <- readRDS(file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_clr_filtered_matrix.rds"))
feature_index <- read.csv(file.path(project_root, "03_covariates_and_outcomes", "processed", "npj_genus_feature_index.csv"), check.names = FALSE)
module_scores <- read.csv(file.path(project_root, "08_ecological_modules_and_network", "processed", "npj_ecological_module_eigengene_scores.csv"), check.names = FALSE)
metadata$SEQN <- as.character(metadata$SEQN)
clr_mat$SEQN <- as.character(clr_mat$SEQN)
module_scores$SEQN <- as.character(module_scores$SEQN)

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
exposure_order <- unname(exposure_map)
alpha_vars <- c("observed_asv", "faith_pd", "shannon_index", "inverse_simpson_index")
design_vars <- c("SDMVPSU", "SDMVSTRA", "WTDR2D_4YR")
base_covariates <- c(
  "age_years", "sex", "race_ethnicity", "education", "marital", "pir",
  "smoking", "alcohol_12plus", "bmi", "total_energy_kcal", "diabetes",
  "hypertension", "recent_dental_visit", "preventive_dental_visit", "rx_use_any"
)
main_covariates <- c(base_covariates, "teeth_present_n", "periodontal_status_proxy", "edentulous")
key_taxa_labels <- c("Neisseria", "Lactobacillus", "Leptotrichia", "Treponema_2", "Prevotellaceae")
key_features <- feature_index[match(key_taxa_labels, feature_index$tax_label), c("feature_id", "tax_label")]
key_features <- key_features[!is.na(key_features$feature_id), ]
key_features$clr_col <- paste0(key_features$feature_id, "__clr")
key_features <- key_features[key_features$clr_col %in% names(clr_mat), ]

write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, fileEncoding = "UTF-8")
num <- function(x) suppressWarnings(as.numeric(as.character(x)))
normal_p <- function(stat) {
  out <- 2 * stats::pnorm(-abs(num(stat)))
  out[!is.finite(out)] <- NA_real_
  out
}
as01 <- function(x, yes_values) as.integer(as.character(x) %in% yes_values)

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

clean_factor_vars <- function(df) {
  for (v in names(df)) {
    if (is.character(df[[v]]) && !v %in% "SEQN") df[[v]] <- factor(df[[v]])
  }
  df
}

drop_covariates <- function(df, covariates, protected = character(0)) {
  covariates <- setdiff(covariates, protected)
  keep <- vapply(covariates, function(v) {
    if (!v %in% names(df)) return(FALSE)
    vals <- df[[v]]
    vals <- vals[!is.na(vals)]
    length(unique(vals)) >= 2
  }, FUN.VALUE = logical(1))
  covariates[keep]
}

make_design <- function(df) {
  df <- clean_factor_vars(df)
  survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTDR2D_4YR, nest = TRUE, data = df)
}

extract_term <- function(fit, term_regex) {
  sm <- tryCatch(as.data.frame(summary(fit)$coefficients), error = function(e) data.frame())
  if (nrow(sm) == 0) return(c(beta = NA_real_, se = NA_real_, stat = NA_real_, p = NA_real_))
  hit <- grep(term_regex, rownames(sm), value = TRUE)
  if (length(hit) == 0) return(c(beta = NA_real_, se = NA_real_, stat = NA_real_, p = NA_real_))
  row <- sm[hit[1], , drop = FALSE]
  p_col <- grep("Pr", names(row), value = TRUE)[1]
  beta <- num(row[[1]][1])
  se <- num(row[[2]][1])
  stat <- num(row[[3]][1])
  p <- if (!is.na(p_col)) num(row[[p_col]][1]) else NA_real_
  if (!is.finite(p) && is.finite(stat)) p <- normal_p(stat)
  c(beta = beta, se = se, stat = stat, p = p)
}

wald_test_terms <- function(fit, terms) {
  coefs <- tryCatch(stats::coef(fit), error = function(e) NULL)
  vc <- tryCatch(stats::vcov(fit), error = function(e) NULL)
  if (is.null(coefs) || is.null(vc)) return(NA_real_)
  terms <- terms[terms %in% names(coefs) & terms %in% rownames(vc) & terms %in% colnames(vc)]
  if (length(terms) == 0) return(NA_real_)
  b <- coefs[terms]
  V <- vc[terms, terms, drop = FALSE]
  keep <- is.finite(b) & apply(V, 1, function(x) all(is.finite(x)))
  terms <- terms[keep]
  if (length(terms) == 0) return(NA_real_)
  b <- coefs[terms]
  V <- vc[terms, terms, drop = FALSE]
  stat <- tryCatch(as.numeric(t(b) %*% solve(V, b)), error = function(e) NA_real_)
  if (!is.finite(stat)) return(NA_real_)
  stats::pchisq(stat, df = length(terms), lower.tail = FALSE)
}

fit_model_term <- function(df, outcome, exposure, covariates, family = gaussian(), weighted = TRUE, term_regex = NULL) {
  covariates <- drop_covariates(df, covariates, protected = c(outcome, exposure))
  needed <- unique(c("SEQN", if (weighted) design_vars else character(0), outcome, exposure, covariates))
  sub <- df[, needed[needed %in% names(df)], drop = FALSE]
  sub <- sub[stats::complete.cases(sub), , drop = FALSE]
  if (nrow(sub) < 100 || length(unique(sub[[outcome]])) < 2) {
    return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, stat = NA_real_, p = NA_real_))
  }
  form <- stats::as.formula(paste(outcome, "~", paste(c(exposure, covariates), collapse = " + ")))
  fit <- tryCatch({
    if (weighted) survey::svyglm(form, design = make_design(sub), family = family) else stats::glm(form, data = clean_factor_vars(sub), family = family)
  }, error = function(e) e)
  if (inherits(fit, "error")) return(c(n = nrow(sub), beta = NA_real_, se = NA_real_, stat = NA_real_, p = NA_real_))
  c(n = nrow(sub), extract_term(fit, if (is.null(term_regex)) paste0("^", exposure, "$") else term_regex))
}

merge_all <- function() {
  ids <- Reduce(intersect, list(metadata$SEQN, clr_mat$SEQN, module_scores$SEQN))
  df <- metadata[match(ids, metadata$SEQN), ]
  cl <- clr_mat[match(ids, clr_mat$SEQN), ]
  ms <- module_scores[match(ids, module_scores$SEQN), ]
  cbind(df, cl[, setdiff(names(cl), "SEQN"), drop = FALSE], ms[, setdiff(names(ms), "SEQN"), drop = FALSE])
}
analysis_df <- merge_all()
analysis_df$periodontitis_modsev <- as01(analysis_df$periodontal_status_proxy, c("Moderate", "Severe"))
analysis_df$periodontitis_severe <- as01(analysis_df$periodontal_status_proxy, c("Severe"))
analysis_df$edentulous_yes <- as01(analysis_df$edentulous, c("Yes"))

rx_files <- file.path(dirname(project_root), "00数据下载", "raw", "nhanes", c("RXQ_RX_F.xpt", "RXQ_RX_G.xpt"))
rx_files <- rx_files[file.exists(rx_files)]
antibiotic_names <- c(
  "AMOXICILLIN", "AZITHROMYCIN", "CIPROFLOXACIN", "DOXYCYCLINE", "CLINDAMYCIN",
  "CEPHALEXIN", "SULFAMETHOXAZOLE", "TRIMETHOPRIM", "METRONIDAZOLE", "LEVOFLOXACIN",
  "MOXIFLOXACIN", "NITROFURANTOIN", "PENICILLIN", "ERYTHROMYCIN", "CLARITHROMYCIN",
  "TETRACYCLINE", "MINOCYCLINE", "AUGMENTIN", "AMPICILLIN", "CEFDINIR",
  "CEFUROXIME", "CEFPROZIL", "CEFIXIME", "CEFTRIAXONE", "GENTAMICIN",
  "VANCOMYCIN", "RIFAMPIN", "LINEZOLID", "MACROBID", "BACTRIM", "KEFLEX"
)
analysis_df$recent_antibiotic_rx <- NA_integer_
if (length(rx_files) > 0) {
  rx_data <- data.table::rbindlist(lapply(rx_files, function(f) as.data.table(haven::read_xpt(f))), fill = TRUE)
  rx_data$SEQN <- as.character(rx_data$SEQN)
  antibiotic_pattern <- paste0("\\b(", paste(antibiotic_names, collapse = "|"), ")")
  rx_data$antibiotic_like_rx <- grepl(antibiotic_pattern, rx_data$RXDDRUG, ignore.case = TRUE)
  antibiotic_inventory <- rx_data[rx_data$antibiotic_like_rx %in% TRUE, .N, by = .(RXDDRUG)]
  antibiotic_inventory <- antibiotic_inventory[order(-N)]
  write_csv(as.data.frame(antibiotic_inventory), file.path(dirs$sens, "processed", "npj_antibiotic_rx_inventory.csv"))
  antibiotic_ids <- unique(rx_data$SEQN[rx_data$antibiotic_like_rx %in% TRUE])
  analysis_df$recent_antibiotic_rx <- as.integer(analysis_df$SEQN %in% antibiotic_ids)
}

theme_cols <- list(blue = "#2A6F97", cyan = "#74A9CF", pale = "#F6E8C3", orange = "#F4A261", red = "#B2182B", navy = "#1F2937", grid = "#E8EEF2")
div_pal <- grDevices::colorRampPalette(c("#3B4CC0", "#D8ECF3", "#F6E8C3", "#F4A261", "#B2182B"))(101)
heatmap_plot <- function(mat, title, zlab, digits = 2) {
  mat <- as.matrix(mat)
  rng <- range(mat, na.rm = TRUE)
  if (!all(is.finite(rng))) rng <- c(-1, 1)
  if (diff(rng) == 0) rng <- rng + c(-1e-6, 1e-6)
  par(mar = c(7.5, 9, 4, 5), family = "sans")
  image(seq_len(ncol(mat)), seq_len(nrow(mat)), t(mat[nrow(mat):1, , drop = FALSE]), col = div_pal, axes = FALSE, xlab = "", ylab = "", main = title, zlim = rng)
  axis(1, at = seq_len(ncol(mat)), labels = colnames(mat), las = 2, cex.axis = 0.75)
  axis(2, at = seq_len(nrow(mat)), labels = rev(rownames(mat)), las = 1, cex.axis = 0.75)
  abline(v = seq(0.5, ncol(mat) + 0.5, 1), col = "white", lwd = 1)
  abline(h = seq(0.5, nrow(mat) + 0.5, 1), col = "white", lwd = 1)
  if (nrow(mat) <= 30 && ncol(mat) <= 12) {
    for (i in seq_len(nrow(mat))) for (j in seq_len(ncol(mat))) {
      val <- mat[rev(seq_len(nrow(mat)))[i], j]
      if (!is.na(val)) text(j, i, sprintf(paste0("%.", digits, "f"), val), cex = 0.45, col = "#111111")
    }
  }
  lx <- ncol(mat) + 0.65
  ly <- seq(0.65, nrow(mat) + 0.35, length.out = 101)
  rasterImage(as.raster(matrix(rev(div_pal), ncol = 1)), lx, min(ly), lx + 0.22, max(ly), xpd = NA)
  text(lx + 0.35, max(ly), sprintf("%.2f", rng[2]), adj = 0, cex = 0.6, xpd = NA)
  text(lx + 0.35, min(ly), sprintf("%.2f", rng[1]), adj = 0, cex = 0.6, xpd = NA)
  text(lx + 0.1, max(ly) + 0.35, zlab, cex = 0.65, xpd = NA)
}

# 19. Oral health outcomes and mediation --------------------------------------
message("Module 19: oral health outcomes and mediation")
oral_covs <- base_covariates
oral_outcomes <- data.frame(
  outcome = c("teeth_present_n", "periodontitis_modsev", "edentulous_yes"),
  outcome_label = c("Number of teeth present", "Moderate/severe periodontitis", "Edentulous"),
  family = c("gaussian", "quasibinomial", "quasibinomial"),
  stringsAsFactors = FALSE
)
mediator_vars <- c(alpha_vars, grep("^ME_M", names(analysis_df), value = TRUE), key_features$clr_col)
mediator_labels <- c(alpha_vars, sub("^ME_", "", grep("^ME_M", names(analysis_df), value = TRUE)), key_features$tax_label)
names(mediator_labels) <- mediator_vars

oral_total <- list()
for (ez in exposure_z) {
  exp_var <- sub("_z$", "", ez)
  for (i in seq_len(nrow(oral_outcomes))) {
    fam <- if (oral_outcomes$family[i] == "gaussian") gaussian() else quasibinomial()
    fit <- fit_model_term(analysis_df, oral_outcomes$outcome[i], ez, oral_covs, family = fam, weighted = TRUE)
    oral_total[[length(oral_total) + 1]] <- data.frame(
      exposure_var = exp_var,
      exposure_label = exposure_map[[exp_var]],
      outcome = oral_outcomes$outcome[i],
      outcome_label = oral_outcomes$outcome_label[i],
      n = fit["n"], beta_total = fit["beta"], se_total = fit["se"], p_total = fit["p"],
      stringsAsFactors = FALSE
    )
  }
}
oral_total <- data.table::rbindlist(oral_total, fill = TRUE)
oral_total$p_fdr <- ave(oral_total$p_total, oral_total$outcome, FUN = function(x) p.adjust(num(x), method = "BH"))

med_results <- list()
for (ez in exposure_z) {
  exp_var <- sub("_z$", "", ez)
  for (med in mediator_vars) {
    a <- fit_model_term(analysis_df, med, ez, oral_covs, family = gaussian(), weighted = TRUE)
    if (!is.finite(a["beta"])) next
    for (i in seq_len(nrow(oral_outcomes))) {
      out <- oral_outcomes$outcome[i]
      fam <- if (oral_outcomes$family[i] == "gaussian") gaussian() else quasibinomial()
      covs_b <- c(oral_covs, ez)
      b <- fit_model_term(analysis_df, out, med, covs_b, family = fam, weighted = TRUE)
      cprime <- fit_model_term(analysis_df, out, ez, c(oral_covs, med), family = fam, weighted = TRUE)
      total <- oral_total[oral_total$exposure_var == exp_var & oral_total$outcome == out, ]
      indirect <- unname(a["beta"]) * unname(b["beta"])
      se_ind <- sqrt((unname(b["beta"])^2) * (unname(a["se"])^2) + (unname(a["beta"])^2) * (unname(b["se"])^2))
      z_ind <- indirect / se_ind
      med_results[[length(med_results) + 1]] <- data.frame(
        exposure_var = exp_var,
        exposure_label = exposure_map[[exp_var]],
        mediator = med,
        mediator_label = mediator_labels[[med]],
        mediator_class = ifelse(med %in% alpha_vars, "alpha_diversity", ifelse(grepl("^ME_M", med), "ecological_module", "key_taxon_CLR")),
        outcome = out,
        outcome_label = oral_outcomes$outcome_label[i],
        outcome_scale = ifelse(oral_outcomes$family[i] == "gaussian", "linear", "logit"),
        n_a = a["n"],
        n_b = b["n"],
        a_beta = a["beta"],
        a_se = a["se"],
        b_beta = b["beta"],
        b_se = b["se"],
        indirect = indirect,
        se_indirect = se_ind,
        z_indirect = z_ind,
        p_indirect = normal_p(z_ind),
        direct_beta = cprime["beta"],
        p_direct = cprime["p"],
        total_beta = total$beta_total[1],
        p_total = total$p_total[1],
        proportion_mediated = ifelse(is.finite(total$beta_total[1]) & abs(total$beta_total[1]) > 1e-8, indirect / total$beta_total[1], NA_real_),
        stringsAsFactors = FALSE
      )
    }
  }
}
med_results <- data.table::rbindlist(med_results, fill = TRUE)
med_results$p_fdr_global <- p.adjust(num(med_results$p_indirect), method = "BH")
write_csv(oral_total, file.path(dirs$oral, "processed", "npj_oral_health_total_effects.csv"))
write_csv(med_results, file.path(dirs$oral, "processed", "npj_oral_microbiome_mediation_product_coefficients.csv"))
writexl::write_xlsx(list(total_effects = as.data.frame(oral_total), mediation_screen = as.data.frame(med_results)), file.path(dirs$oral, "processed", "npj_oral_health_mediation_results.xlsx"))
med_count <- med_results[num(med_results$p_indirect) < 0.05, .N, by = .(exposure_label, outcome_label)]
med_mat <- matrix(0, nrow = length(exposure_order), ncol = nrow(oral_outcomes), dimnames = list(exposure_order, oral_outcomes$outcome_label))
for (i in seq_len(nrow(med_count))) med_mat[med_count$exposure_label[i], med_count$outcome_label[i]] <- med_count$N[i]
save_plot(file.path(dirs$oral, "figures", "figure19_mediation_evidence_heatmap.png"), file.path(dirs$oral, "figures", "figure19_mediation_evidence_heatmap.pdf"), 2100, 1700, function() heatmap_plot(med_mat, "Diet-microbiome-oral health mediation evidence", "nominal indirect paths", 0))
top_med <- med_results[order(num(p_indirect))][seq_len(min(20, nrow(med_results)))]
save_plot(file.path(dirs$oral, "figures", "figure19_top_mediation_paths.png"), file.path(dirs$oral, "figures", "figure19_top_mediation_paths.pdf"), 2600, 1800, function() {
  par(mar = c(5, 13, 4, 2), family = "sans")
  labels <- paste(top_med$exposure_label, "\u2192", top_med$mediator_label, "\u2192", top_med$outcome_label)
  y <- seq_len(nrow(top_med))
  x <- num(top_med$indirect)
  se <- num(top_med$se_indirect)
  plot(x, y, yaxt = "n", pch = 21, bg = ifelse(x > 0, theme_cols$orange, theme_cols$blue), col = theme_cols$navy, xlab = "Indirect effect", ylab = "", main = "Top microbiome-mediated oral health pathways", ylim = c(0.5, length(y) + 0.5))
  axis(2, at = y, labels = labels, las = 1, cex.axis = 0.58)
  abline(v = 0, col = theme_cols$grid)
  segments(x - 1.96 * se, y, x + 1.96 * se, y, col = theme_cols$navy)
})

# 20. Key taxa dose-response ---------------------------------------------------
message("Module 20: key taxa dose-response")
dose_results <- list()
curve_rows <- list()
for (ez in exposure_z) {
  exp_var <- sub("_z$", "", ez)
  for (j in seq_len(nrow(key_features))) {
    tax_col <- key_features$clr_col[j]
    df <- analysis_df[, unique(c("SEQN", design_vars, tax_col, ez, paste0(exp_var, "_q4"), main_covariates)), drop = FALSE]
    df <- df[stats::complete.cases(df), , drop = FALSE]
    covs <- drop_covariates(df, main_covariates, protected = c(tax_col, ez))
    if (nrow(df) < 100) next
    basis <- splines::ns(num(df[[ez]]), df = 3)
    colnames(basis) <- paste0("spline", 1:3)
    df <- cbind(df, basis)
    des <- make_design(df)
    fit_spline <- tryCatch(survey::svyglm(stats::as.formula(paste(tax_col, "~ spline1 + spline2 + spline3 +", paste(covs, collapse = " + "))), design = des), error = function(e) e)
    p_spline <- NA_real_
    if (!inherits(fit_spline, "error")) {
      p_spline <- wald_test_terms(fit_spline, c("spline1", "spline2", "spline3"))
    }
    trend <- fit_model_term(analysis_df, tax_col, ez, main_covariates, family = gaussian(), weighted = TRUE)
    qnum <- paste0(exp_var, "_qnum")
    analysis_df[[qnum]] <- match(as.character(analysis_df[[paste0(exp_var, "_q4")]]), paste0("Q", 1:4))
    qtrend <- fit_model_term(analysis_df, tax_col, qnum, main_covariates, family = gaussian(), weighted = TRUE)
    dose_results[[length(dose_results) + 1]] <- data.frame(
      exposure_var = exp_var,
      exposure_label = exposure_map[[exp_var]],
      tax_label = key_features$tax_label[j],
      feature_id = key_features$feature_id[j],
      n = nrow(df),
      beta_linear = trend["beta"],
      se_linear = trend["se"],
      p_linear = trend["p"],
      beta_qtrend = qtrend["beta"],
      p_qtrend = qtrend["p"],
      p_spline_overall = p_spline,
      stringsAsFactors = FALSE
    )
    if (!inherits(fit_spline, "error")) {
      grid_x <- seq(quantile(num(df[[ez]]), 0.02, na.rm = TRUE), quantile(num(df[[ez]]), 0.98, na.rm = TRUE), length.out = 80)
      newdata <- df[rep(1, length(grid_x)), , drop = FALSE]
      newdata[[ez]] <- grid_x
      new_basis <- predict(splines::ns(num(df[[ez]]), df = 3), newx = grid_x)
      colnames(new_basis) <- paste0("spline", 1:3)
      newdata[, paste0("spline", 1:3)] <- new_basis
      for (cv in covs) {
        if (is.numeric(df[[cv]])) newdata[[cv]] <- stats::median(df[[cv]], na.rm = TRUE)
        if (is.factor(df[[cv]]) || is.character(df[[cv]])) newdata[[cv]] <- names(sort(table(df[[cv]]), decreasing = TRUE))[1]
      }
      pred_obj <- tryCatch(predict(fit_spline, newdata = newdata, type = "response", se.fit = TRUE), error = function(e) e)
      if (inherits(pred_obj, "error")) {
        pred <- rep(NA_real_, length(grid_x))
        se_fit <- rep(NA_real_, length(grid_x))
      } else if (is.list(pred_obj) && !is.null(pred_obj$fit)) {
        pred <- as.numeric(pred_obj$fit)
        se_fit <- as.numeric(pred_obj$se.fit)
      } else {
        pred <- as.numeric(pred_obj)
        se_fit <- tryCatch(as.numeric(survey::SE(pred_obj)), error = function(e) rep(NA_real_, length(grid_x)))
      }
      if (length(se_fit) != length(grid_x)) se_fit <- rep(NA_real_, length(grid_x))
      curve_rows[[length(curve_rows) + 1]] <- data.frame(
        exposure_label = exposure_map[[exp_var]],
        exposure_var = exp_var,
        tax_label = key_features$tax_label[j],
        x = grid_x,
        predicted_clr = pred,
        se_fit = se_fit,
        ci_low = pred - 1.96 * se_fit,
        ci_high = pred + 1.96 * se_fit,
        stringsAsFactors = FALSE
      )
    }
  }
}
dose_results <- data.table::rbindlist(dose_results, fill = TRUE)
dose_results$p_fdr_spline <- p.adjust(num(dose_results$p_spline_overall), method = "BH")
curve_df <- data.table::rbindlist(curve_rows, fill = TRUE)
write_csv(dose_results, file.path(dirs$dose, "processed", "npj_key_taxa_dose_response_results.csv"))
write_csv(curve_df, file.path(dirs$dose, "processed", "npj_key_taxa_rcs_curve_predictions.csv"))
writexl::write_xlsx(list(dose_response = as.data.frame(dose_results), curve_predictions = as.data.frame(curve_df)), file.path(dirs$dose, "processed", "npj_key_taxa_dose_response_results.xlsx"))
dose_mat <- matrix(NA_real_, nrow = length(key_features$tax_label), ncol = length(exposure_order), dimnames = list(key_features$tax_label, exposure_order))
for (i in seq_len(nrow(dose_results))) dose_mat[dose_results$tax_label[i], dose_results$exposure_label[i]] <- dose_results$beta_linear[i]
save_plot(file.path(dirs$dose, "figures", "figure20_key_taxa_linear_beta_heatmap.png"), file.path(dirs$dose, "figures", "figure20_key_taxa_linear_beta_heatmap.pdf"), 2200, 1500, function() heatmap_plot(dose_mat, "Key taxa dose-response: linear effect", "beta", 2))
top_curve <- dose_results[is.finite(num(p_spline_overall))][order(num(p_spline_overall))]
if (nrow(top_curve) == 0) top_curve <- dose_results[order(num(p_linear))]
top_curve <- top_curve[seq_len(min(6, nrow(top_curve)))]
save_plot(file.path(dirs$dose, "figures", "figure20_key_taxa_rcs_top_curves.png"), file.path(dirs$dose, "figures", "figure20_key_taxa_rcs_top_curves.pdf"), 2600, 1800, function() {
  par(mfrow = c(2, 3), mar = c(4, 4, 3, 1), family = "sans")
  for (i in seq_len(nrow(top_curve))) {
    sub <- curve_df[curve_df$exposure_var == top_curve$exposure_var[i] & curve_df$tax_label == top_curve$tax_label[i], ]
    sub <- sub[order(sub$x), ]
    y_range <- range(c(sub$ci_low, sub$ci_high, sub$predicted_clr), na.rm = TRUE)
    if (!all(is.finite(y_range))) y_range <- range(sub$predicted_clr, na.rm = TRUE)
    plot(sub$x, sub$predicted_clr, type = "n", ylim = y_range, xlab = paste0(top_curve$exposure_label[i], " z-score"), ylab = "Predicted CLR", main = paste0(top_curve$tax_label[i], "\nP-spline=", sprintf("%.3g", num(top_curve$p_spline_overall[i]))))
    grid(col = theme_cols$grid)
    if (all(c("ci_low", "ci_high") %in% names(sub)) && any(is.finite(sub$ci_low) & is.finite(sub$ci_high))) {
      ok <- is.finite(sub$x) & is.finite(sub$ci_low) & is.finite(sub$ci_high)
      polygon(c(sub$x[ok], rev(sub$x[ok])), c(sub$ci_low[ok], rev(sub$ci_high[ok])), col = grDevices::adjustcolor(theme_cols$blue, alpha.f = 0.18), border = NA)
    }
    lines(sub$x, sub$predicted_clr, lwd = 2.4, col = theme_cols$blue)
  }
})

# 21. Functional prediction feasibility ---------------------------------------
message("Module 21: functional prediction feasibility")
all_files <- list.files(project_root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
ext <- tolower(tools::file_ext(all_files))
inventory <- data.frame(path = all_files, file_name = basename(all_files), extension = ext, size_bytes = file.info(all_files)$size, stringsAsFactors = FALSE)
inventory$picrust2_relevant <- inventory$extension %in% c("fasta", "fa", "fastq", "fq", "biom", "qza", "qzv", "tre", "nwk")
inventory$role_guess <- ifelse(inventory$extension %in% c("fasta", "fa"), "representative_sequences", ifelse(inventory$extension %in% c("biom", "qza"), "feature_table_or_qiime2_artifact", ifelse(grepl("taxonomy|taxa", inventory$file_name, ignore.case = TRUE), "taxonomy_annotation", "other")))
picrust_ready <- any(inventory$extension %in% c("fasta", "fa")) && any(inventory$extension %in% c("biom", "qza"))
write_csv(inventory[inventory$picrust2_relevant | grepl("taxonomy|genus-count|genus-relative", inventory$file_name, ignore.case = TRUE), ], file.path(dirs$func, "processed", "npj_picrust2_input_inventory.csv"))
report <- c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste0("PICRUSt2-ready input detected: ", picrust_ready),
  "Required for formal PICRUSt2: representative ASV/OTU sequences in FASTA plus feature table/count table mapped to sequence IDs.",
  "Current project contains genus-level count/relative abundance matrices and taxonomy annotation, but no representative FASTA/BIOM/QIIME2 feature artifacts were detected under 0510.",
  "Conclusion: formal functional prediction was not run to avoid generating unsupported pathway results from genus-only summaries.",
  "Recommended next input: original DADA2 ASV table and representative sequence FASTA from the NHANES oral microbiome processing pipeline."
)
writeLines(report, file.path(dirs$func, "processed", "npj_picrust2_feasibility_report.txt"), useBytes = TRUE)
save_plot(file.path(dirs$func, "figures", "figure21_picrust2_feasibility_flow.png"), file.path(dirs$func, "figures", "figure21_picrust2_feasibility_flow.pdf"), 2200, 1200, function() {
  par(mar = c(1, 1, 3, 1), family = "sans")
  plot.new()
  title("PICRUSt2 functional prediction feasibility")
  xs <- c(0.12, 0.38, 0.64, 0.88)
  labs <- c("Genus matrix\navailable", "Representative\nsequences missing", "BIOM/QIIME2 ASV\ntable missing", "Formal PICRUSt2\nnot run")
  cols <- c(theme_cols$blue, theme_cols$orange, theme_cols$orange, theme_cols$red)
  for (i in seq_along(xs)) {
    rect(xs[i] - 0.1, 0.42, xs[i] + 0.1, 0.62, col = adjustcolor(cols[i], alpha.f = 0.18), border = cols[i], lwd = 2)
    text(xs[i], 0.52, labs[i], cex = 0.9)
    if (i < length(xs)) arrows(xs[i] + 0.11, 0.52, xs[i + 1] - 0.11, 0.52, length = 0.08, col = theme_cols$navy, lwd = 1.6)
  }
})

# 22. Medication/dental sensitivity -------------------------------------------
message("Module 22: medication and dental sensitivity")
sens_scenarios <- list(
  main = rep(TRUE, nrow(analysis_df)),
  no_recent_antibiotic_rx = analysis_df$recent_antibiotic_rx == 0,
  no_rx_use = analysis_df$rx_use_any == "No",
  no_recent_dental_visit = analysis_df$recent_dental_visit == ">1 year/never",
  no_preventive_dental_visit = analysis_df$preventive_dental_visit != "Preventive" & !is.na(analysis_df$preventive_dental_visit),
  no_rx_and_no_recent_dental = analysis_df$rx_use_any == "No" & analysis_df$recent_dental_visit == ">1 year/never",
  no_antibiotic_rx_and_no_recent_dental = analysis_df$recent_antibiotic_rx == 0 & analysis_df$recent_dental_visit == ">1 year/never"
)
sens_outcomes <- c(alpha_vars, key_features$clr_col)
sens_labels <- c(alpha_vars, key_features$tax_label)
names(sens_labels) <- sens_outcomes
sens_results <- list()
for (scenario in names(sens_scenarios)) {
  df_s <- analysis_df[sens_scenarios[[scenario]] %in% TRUE, ]
  for (out in sens_outcomes) {
    for (ez in exposure_z) {
      exp_var <- sub("_z$", "", ez)
      fit <- fit_model_term(df_s, out, ez, main_covariates, gaussian(), weighted = TRUE)
      sens_results[[length(sens_results) + 1]] <- data.frame(scenario = scenario, outcome = out, outcome_label = sens_labels[[out]], outcome_class = ifelse(out %in% alpha_vars, "alpha", "key_taxon_CLR"), exposure_var = exp_var, exposure_label = exposure_map[[exp_var]], n = fit["n"], beta = fit["beta"], se = fit["se"], p_value = fit["p"], stringsAsFactors = FALSE)
    }
  }
}
sens_results <- data.table::rbindlist(sens_results, fill = TRUE)
main_ref <- sens_results[scenario == "main", .(outcome, exposure_var, beta_main = num(beta), p_main = num(p_value))]
sens_results <- merge(sens_results, main_ref, by = c("outcome", "exposure_var"), all.x = TRUE)
sens_results$beta_delta_from_main <- num(sens_results$beta) - num(sens_results$beta_main)
sens_results$direction_consistent_with_main <- sign(num(sens_results$beta)) == sign(num(sens_results$beta_main))
sens_summary <- sens_results[scenario != "main", .(
  n_models = .N,
  n_direction_consistent = sum(direction_consistent_with_main, na.rm = TRUE),
  median_abs_delta = median(abs(beta_delta_from_main), na.rm = TRUE)
), by = scenario]
write_csv(sens_results, file.path(dirs$sens, "processed", "npj_medication_dental_sensitivity_results.csv"))
write_csv(sens_summary, file.path(dirs$sens, "processed", "npj_medication_dental_sensitivity_summary.csv"))
writexl::write_xlsx(list(sensitivity_results = as.data.frame(sens_results), summary = as.data.frame(sens_summary)), file.path(dirs$sens, "processed", "npj_medication_dental_sensitivity_results.xlsx"))
sens_heat <- sens_results[scenario != "main" & outcome == "shannon_index", ]
sens_mat <- matrix(NA_real_, nrow = length(unique(sens_heat$scenario)), ncol = length(exposure_order), dimnames = list(unique(sens_heat$scenario), exposure_order))
for (i in seq_len(nrow(sens_heat))) sens_mat[sens_heat$scenario[i], sens_heat$exposure_label[i]] <- sens_heat$beta_delta_from_main[i]
save_plot(file.path(dirs$sens, "figures", "figure22_sensitivity_shannon_delta_heatmap.png"), file.path(dirs$sens, "figures", "figure22_sensitivity_shannon_delta_heatmap.pdf"), 2300, 1500, function() heatmap_plot(sens_mat, "Medication/dental sensitivity: Shannon beta delta", "delta beta", 3))
save_plot(file.path(dirs$sens, "figures", "figure22_sensitivity_direction_consistency.png"), file.path(dirs$sens, "figures", "figure22_sensitivity_direction_consistency.pdf"), 2000, 1300, function() {
  par(mar = c(7, 5, 4, 1), family = "sans")
  pct <- sens_summary$n_direction_consistent / sens_summary$n_models * 100
  bp <- barplot(pct, names.arg = sens_summary$scenario, las = 2, col = theme_cols$blue, border = NA, ylim = c(0, 100), ylab = "Direction consistency with main analysis (%)", main = "Robustness after excluding medication/dental intervention groups")
  text(bp, pct + 3, sprintf("%.1f%%", pct), cex = 0.75)
})

# 23. Weighted vs unweighted comparison ---------------------------------------
message("Module 23: weighted vs unweighted comparison")
wu_results <- list()
wu_outcomes <- c(alpha_vars, key_features$clr_col, "teeth_present_n", "periodontitis_modsev", "edentulous_yes")
wu_labels <- c(alpha_vars, key_features$tax_label, "Number of teeth present", "Moderate/severe periodontitis", "Edentulous")
names(wu_labels) <- wu_outcomes
for (out in wu_outcomes) {
  fam <- if (out %in% c("periodontitis_modsev", "edentulous_yes")) quasibinomial() else gaussian()
  covs <- if (out %in% c("teeth_present_n", "periodontitis_modsev", "edentulous_yes")) oral_covs else main_covariates
  for (ez in exposure_z) {
    exp_var <- sub("_z$", "", ez)
    w <- fit_model_term(analysis_df, out, ez, covs, fam, weighted = TRUE)
    u <- fit_model_term(analysis_df, out, ez, covs, fam, weighted = FALSE)
    wu_results[[length(wu_results) + 1]] <- data.frame(analysis_family = "alpha_taxa_oral_outcomes", outcome = out, outcome_label = wu_labels[[out]], exposure_var = exp_var, exposure_label = exposure_map[[exp_var]], n_weighted = w["n"], beta_weighted = w["beta"], se_weighted = w["se"], p_weighted = w["p"], n_unweighted = u["n"], beta_unweighted = u["beta"], se_unweighted = u["se"], p_unweighted = u["p"], stringsAsFactors = FALSE)
  }
}
pcoa_path <- file.path(project_root, "06_beta_diversity_PERMANOVA_dbRDA", "processed", "npj_beta_pcoa_scores_all_diet_quartiles.csv")
if (file.exists(pcoa_path)) {
  pcoa_scores <- read.csv(pcoa_path, check.names = FALSE)
  pcoa_scores$SEQN <- as.character(pcoa_scores$SEQN)
  for (metric in unique(pcoa_scores$beta_metric_label)) {
    for (exp_var in exposure_vars) {
      sub <- pcoa_scores[pcoa_scores$beta_metric_label == metric & pcoa_scores$exposure_var == exp_var, c("SEQN", "PCoA1", "PCoA2")]
      sub <- merge(metadata, sub, by = "SEQN")
      for (axis in c("PCoA1", "PCoA2")) {
        w <- fit_model_term(sub, axis, paste0(exp_var, "_z"), main_covariates, gaussian(), weighted = TRUE)
        u <- fit_model_term(sub, axis, paste0(exp_var, "_z"), main_covariates, gaussian(), weighted = FALSE)
        wu_results[[length(wu_results) + 1]] <- data.frame(analysis_family = paste0("beta_PCoA_", metric), outcome = axis, outcome_label = paste(metric, axis), exposure_var = exp_var, exposure_label = exposure_map[[exp_var]], n_weighted = w["n"], beta_weighted = w["beta"], se_weighted = w["se"], p_weighted = w["p"], n_unweighted = u["n"], beta_unweighted = u["beta"], se_unweighted = u["se"], p_unweighted = u["p"], stringsAsFactors = FALSE)
      }
    }
  }
}
wu_results <- data.table::rbindlist(wu_results, fill = TRUE)
wu_results$beta_delta_unweighted_minus_weighted <- num(wu_results$beta_unweighted) - num(wu_results$beta_weighted)
wu_results$direction_consistent <- sign(num(wu_results$beta_weighted)) == sign(num(wu_results$beta_unweighted))
wu_summary <- wu_results[, .(n_models = .N, n_direction_consistent = sum(direction_consistent, na.rm = TRUE), median_abs_delta = median(abs(beta_delta_unweighted_minus_weighted), na.rm = TRUE)), by = analysis_family]
write_csv(wu_results, file.path(dirs$wu, "processed", "npj_weighted_unweighted_comparison_results.csv"))
write_csv(wu_summary, file.path(dirs$wu, "processed", "npj_weighted_unweighted_comparison_summary.csv"))
writexl::write_xlsx(list(comparison_results = as.data.frame(wu_results), summary = as.data.frame(wu_summary)), file.path(dirs$wu, "processed", "npj_weighted_unweighted_comparison_results.xlsx"))
save_plot(file.path(dirs$wu, "figures", "figure23_weighted_vs_unweighted_beta_scatter.png"), file.path(dirs$wu, "figures", "figure23_weighted_vs_unweighted_beta_scatter.pdf"), 1900, 1700, function() {
  par(mar = c(5, 5, 4, 1), family = "sans")
  x <- num(wu_results$beta_weighted)
  y <- num(wu_results$beta_unweighted)
  ok <- is.finite(x) & is.finite(y)
  lim <- range(c(x[ok], y[ok]), na.rm = TRUE)
  plot(x[ok], y[ok], pch = 21, bg = adjustcolor(theme_cols$blue, alpha.f = 0.55), col = theme_cols$navy, xlab = "Survey-weighted beta", ylab = "Unweighted beta", main = "Weighted vs unweighted model comparison", xlim = lim, ylim = lim)
  abline(0, 1, col = theme_cols$red, lwd = 1.5, lty = 2)
  grid(col = theme_cols$grid)
})

writeLines(c(
  paste0("Run time: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "Modules completed: 19 oral health mediation, 20 key taxa dose response, 21 PICRUSt2 feasibility, 22 medication/dental sensitivity, 23 weighted-unweighted comparison.",
  paste0("Oral total-effect models: ", nrow(oral_total)),
  paste0("Mediation paths screened: ", nrow(med_results), "; nominal indirect paths: ", sum(num(med_results$p_indirect) < 0.05, na.rm = TRUE)),
  paste0("Key taxa dose-response models: ", nrow(dose_results)),
  paste0("PICRUSt2-ready input detected: ", picrust_ready),
  paste0("Sensitivity models: ", nrow(sens_results)),
  paste0("Weighted-unweighted comparison models: ", nrow(wu_results))
), file.path(project_root, "00_protocol_and_log", "npj_19_23_extension_analyses_summary.txt"), useBytes = TRUE)

message("Extension analyses 19-23 completed.")

