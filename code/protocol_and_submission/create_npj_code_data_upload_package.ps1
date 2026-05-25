param(
    [string]$ReleaseName = "NPJ_Biofilms_code_data_upload_20260525"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Out = Join-Path $Root "13_manuscript_and_submission\$ReleaseName"
$Submission = Join-Path $Root "13_manuscript_and_submission\NPJ_Biofilms_submission_package_20260524"

function Ensure-Dir([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Copy-FileIfExists([string]$Source, [string]$DestinationDir) {
    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Ensure-Dir $DestinationDir
        Copy-Item -LiteralPath $Source -Destination $DestinationDir -Force
    }
}

function Copy-TreeIfExists([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source -PathType Container) {
        Ensure-Dir (Split-Path -Parent $Destination)
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    }
}

function Copy-ModuleArtifacts([string]$ModuleName, [string]$DestinationName = "") {
    if ($DestinationName -eq "") { $DestinationName = $ModuleName }
    $src = Join-Path $Root $ModuleName
    if (!(Test-Path -LiteralPath $src -PathType Container)) { return }
    $dst = Join-Path $Out "results_by_module\$DestinationName"
    Ensure-Dir $dst

    Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".R", ".py", ".ps1") } |
        ForEach-Object { Copy-FileIfExists $_.FullName (Join-Path $dst "code") }

    foreach ($sub in @("processed", "logs", "figures")) {
        Copy-TreeIfExists (Join-Path $src $sub) (Join-Path $dst $sub)
    }
}

Ensure-Dir $Out
Ensure-Dir (Join-Path $Out "code")
Ensure-Dir (Join-Path $Out "data")
Ensure-Dir (Join-Path $Out "submission_outputs")
Ensure-Dir (Join-Path $Out "final_figures")

# Core orchestration and manuscript/figure build scripts.
$coreScripts = @(
    "visualize_yuting_style_extensions.py",
    "run_15_18_visualizations_all.R",
    "run_15_18_supplementary_modules.R",
    "run_19_23_extension_analyses.R",
    "fix_15_18_pvalues_outputs.R",
    "visualize_15_18_supplementary_modules.R",
    "visualize_18_bridge_heatmap.R",
    "visualize_18_bridge_heatmap_v2.R"
)
foreach ($f in $coreScripts) {
    Copy-FileIfExists (Join-Path $Root $f) (Join-Path $Out "code\orchestration")
}

$protocolScripts = @(
    "README_protocol.md",
    "build_npj_biofilms_submission_package.py",
    "apply_jama_network_open_figure_style.py",
    "compose_figure1_npj_multipanel.py",
    "compose_figure1_standard_multipanel.py",
    "render_npj_with_libreoffice.py",
    "create_npj_code_data_upload_package.ps1"
)
foreach ($f in $protocolScripts) {
    Copy-FileIfExists (Join-Path $Root "00_protocol_and_log\$f") (Join-Path $Out "code\protocol_and_submission")
}

# Public input manifest and small reference files. Very large public distance matrices are listed separately.
Copy-FileIfExists (Join-Path $Root "01_data_inputs\README_data_inputs.md") (Join-Path $Out "data\public_input_manifest")
Copy-FileIfExists (Join-Path $Root "01_data_inputs\data_input_manifest.csv") (Join-Path $Out "data\public_input_manifest")
Copy-FileIfExists (Join-Path $Root "01_data_inputs\setup_data_inputs.ps1") (Join-Path $Out "data\public_input_manifest")
Copy-TreeIfExists (Join-Path $Root "01_data_inputs\logs") (Join-Path $Out "data\public_input_manifest\logs")
Copy-TreeIfExists (Join-Path $Root "01_data_inputs\taxonomy") (Join-Path $Out "data\public_input_manifest\taxonomy")
Copy-TreeIfExists (Join-Path $Root "01_data_inputs\previous_results_reference") (Join-Path $Out "data\public_input_manifest\previous_results_reference")

# Derived analysis inputs used by downstream models.
Copy-TreeIfExists (Join-Path $Root "02_exposure_diet_indices\processed") (Join-Path $Out "data\derived_analysis_inputs\02_exposure_diet_indices_processed")
Copy-TreeIfExists (Join-Path $Root "03_covariates_and_outcomes\processed") (Join-Path $Out "data\derived_analysis_inputs\03_covariates_and_outcomes_processed")

# Module-level reproducibility outputs.
$modules = @(
    "02_exposure_diet_indices",
    "03_covariates_and_outcomes",
    "04_descriptive_and_diet_architecture",
    "05_alpha_diversity",
    "06_beta_diversity_PERMANOVA_dbRDA",
    "07_differential_abundance_MaAsLin2_ANCOMBC2_CLR",
    "08_ecological_modules_and_network",
    "09_recurrent_taxa_LEfSe_UpSet",
    "10_subgroup_effect_modification",
    "11_sensitivity_analysis",
    "14_joint_core_evidence_map",
    "15_da_validation_ANCOMBC2_MaAsLin3",
    "16_community_typing",
    "17_diet_PCA_patterns",
    "18_core_module_scores",
    "20_key_taxa_dose_response",
    "21_functional_prediction_feasibility",
    "22_medication_dental_sensitivity",
    "23_weighted_unweighted_comparison"
)
foreach ($m in $modules) { Copy-ModuleArtifacts $m }

# Legacy folder names are preserved inside source code, but public-facing destination names use non-causal wording.
Copy-ModuleArtifacts "12_mediation_analysis" "12_noncausal_path_summaries"
Copy-ModuleArtifacts "19_oral_health_outcomes_mediation" "19_oral_health_path_extension"

# Consolidated figure/table packages used in the manuscript.
Copy-TreeIfExists (Join-Path $Root "12_figures_tables_npj\yuting_style_visualizations") (Join-Path $Out "final_figures\yuting_style_visualizations")
Copy-TreeIfExists (Join-Path $Submission "figures_for_upload") (Join-Path $Out "final_figures\figures_for_upload")
Copy-TreeIfExists (Join-Path $Submission "main_figures") (Join-Path $Out "final_figures\main_figures")
Copy-TreeIfExists (Join-Path $Submission "supplementary_figures") (Join-Path $Out "final_figures\supplementary_figures")

# Journal upload data and final reference outputs.
$submissionFiles = @(
    "Source_Data.xlsx",
    "Supplementary_Data_1_numeric_tables.xlsx",
    "Manuscript_Dietary_inflammatory_potential_oral_microbiome_npj.docx",
    "Supplementary_Information_Diet_oral_microbiome_npj.docx",
    "Cover_letter_npj_Biofilms_and_Microbiomes.docx",
    "NPJ_submission_checklist_and_notes.md",
    "NPJ_submission_manifest.md",
    "JAMA_Network_Open_figure_style_notes.md"
)
foreach ($f in $submissionFiles) {
    Copy-FileIfExists (Join-Path $Submission $f) (Join-Path $Out "submission_outputs")
}
Copy-TreeIfExists (Join-Path $Submission "pdf") (Join-Path $Out "submission_outputs\pdf")

# Track large public-source input files that are not duplicated into the lightweight upload package.
$largeManifest = Join-Path $Out "data\large_public_inputs_not_copied.csv"
Get-ChildItem -LiteralPath (Join-Path $Root "01_data_inputs") -Recurse -File |
    Where-Object { $_.Length -ge 50000000 } |
    Select-Object @{Name="relative_path";Expression={$_.FullName.Substring($Root.Length + 1)}},
                  @{Name="size_bytes";Expression={$_.Length}},
                  @{Name="note";Expression={"Large public or reconstructed input; keep in institutional archive or upload separately to Zenodo if full raw archive is required."}} |
    Export-Csv -Path $largeManifest -NoTypeInformation -Encoding UTF8

# Public README.
$readme = @"
# Code and data upload package

Study: Dietary inflammatory potential and oral microbiome ecology in NHANES
Prepared: 2026-05-25

This folder contains the code, derived data tables, module-level results, final figure files and manuscript-supporting data needed for repository or reviewer upload.

## Folder structure

- code/orchestration: top-level R/Python scripts used to run grouped analyses and visualization extensions.
- code/protocol_and_submission: final manuscript, figure and package-building scripts.
- data/public_input_manifest: source-data README, input manifest and small taxonomy/reference files.
- data/derived_analysis_inputs: processed diet, metadata, alpha/beta/taxon matrices used by downstream analyses.
- data/large_public_inputs_not_copied.csv: very large public-source files not duplicated into this lightweight upload package.
- results_by_module: processed tables, logs and figures by analysis module.
- final_figures: upload-ready main and supplementary figure files.
- submission_outputs: Source Data, Supplementary Data 1 and final manuscript-supporting files.

## Reproducibility notes

Raw NHANES public-use files and very large public oral-microbiome distance matrices are not duplicated here by default. They are listed in data/large_public_inputs_not_copied.csv and in data/public_input_manifest/data_input_manifest.csv. The analysis package includes derived matrices and numeric tables sufficient to audit the manuscript results and figures.

Recommended execution order:

1. Review data/public_input_manifest/README_data_inputs.md and data_input_manifest.csv.
2. Rebuild analysis inputs with 02_exposure_diet_indices and 03_covariates_and_outcomes scripts if starting from raw public files.
3. Run module scripts in numerical order for modules 04-23 as needed.
4. Regenerate JAMA-style figures with code/protocol_and_submission/apply_jama_network_open_figure_style.py.
5. Rebuild the npj submission documents with code/protocol_and_submission/build_npj_biofilms_submission_package.py.

## Software

R and Python were used. Main R packages include survey, vegan, ggplot2 and data-wrangling packages. Main Python packages include pandas, numpy, matplotlib, seaborn, pillow, python-docx and openpyxl.

## Important interpretation note

Oral-health path summaries are non-causal, exploratory association-path summaries. They should not be interpreted as temporal mediation or intervention effects.

## Repository note

Before public release, add the final GitHub/Zenodo URL and DOI to the manuscript Code availability statement and to this README.
"@
$readme | Set-Content -Path (Join-Path $Out "README.md") -Encoding UTF8

# Machine-readable file manifest.
Get-ChildItem -LiteralPath $Out -Recurse -File |
    Where-Object { $_.FullName -notmatch "\\_tmp_ascii\\" } |
    Select-Object @{Name="relative_path";Expression={$_.FullName.Substring($Out.Length + 1)}},
                  @{Name="size_bytes";Expression={$_.Length}},
                  LastWriteTime |
    Sort-Object relative_path |
    Export-Csv -Path (Join-Path $Out "file_manifest.csv") -NoTypeInformation -Encoding UTF8

Write-Host "Created upload package:"
Write-Host $Out
