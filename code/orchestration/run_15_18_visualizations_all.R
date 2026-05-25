options(stringsAsFactors = FALSE)

args_full <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_full, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = TRUE)
  project_root <- dirname(script_path)
} else {
  project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
}

rscript <- file.path(R.home("bin"), "Rscript.exe")
if (!file.exists(rscript)) rscript <- file.path(R.home("bin"), "Rscript")

main_script <- file.path(project_root, "visualize_15_18_supplementary_modules.R")
bridge_script <- file.path(project_root, "visualize_18_bridge_heatmap_v2.R")

message("Running module 15-18 visualization script...")
status_main <- system2(rscript, shQuote(main_script))
if (!identical(status_main, 0L)) {
  message("Main visualization script returned status ", status_main, "; already-generated figures are retained.")
}

message("Running corrected module 18 bridge heatmap script...")
status_bridge <- system2(rscript, shQuote(bridge_script))
if (!identical(status_bridge, 0L)) stop("Bridge visualization failed with status ", status_bridge)

message("All module 15-18 visualizations are available in 12_figures_tables_npj/figures_15_18_visualizations.")
