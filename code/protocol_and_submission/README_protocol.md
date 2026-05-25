# 0510 npj Biofilms and Microbiomes 冲刺版分析目录说明

本文件夹用于按照 `npj Biofilms and Microbiomes` 的投稿定位，重新组织“膳食指数与口腔微生物生态特征”研究的分析流程。整体思路是从原来的多膳食指数关联分析，升级为以膳食炎症潜能、膳食质量、植物性饮食质量和口腔微生物生态结构为主线的机制型分析框架。

## 目录结构

| 文件夹 | 主要用途 |
|---|---|
| `00_protocol_and_log` | 存放分析方案、日志、版本说明和关键决策记录 |
| `01_data_inputs` | 存放原始或上一阶段清洗后的输入数据索引、数据字典和导入脚本 |
| `02_exposure_diet_indices` | 整理 E-DII、HEI-2015、DASH、aMED、hPDI、uPDI、PHDI、DII 等膳食指数 |
| `03_covariates_and_outcomes` | 整理协变量、alpha diversity、beta diversity、属水平丰度和样本纳入排除变量 |
| `04_descriptive_and_diet_architecture` | 描述性分析、基线表、膳食指数相关性和膳食指数结构分析 |
| `05_alpha_diversity` | survey-weighted alpha diversity 线性模型和 RCS 非线性分析 |
| `06_beta_diversity_PERMANOVA_dbRDA` | PERMANOVA、PCoA、dbRDA/constrained ordination 等群落结构分析 |
| `07_differential_abundance_MaAsLin2_ANCOMBC2_CLR` | MaAsLin2、ANCOM-BC2、survey-weighted CLR 属水平模型和差异丰度验证 |
| `08_ecological_modules_and_network` | 菌群生态模块、共现网络、diet-sensitive microbial modules 分析 |
| `09_recurrent_taxa_LEfSe_UpSet` | LEfSe 探索性差异菌、反复出现菌属、UpSet 图和系统分类树图 |
| `10_subgroup_effect_modification` | 性别、吸烟状态、牙周状态等亚组和交互作用分析 |
| `11_sensitivity_analysis` | 排除无牙颌、极端能量、抗生素/药物使用者、Day 1 vs 两日平均等敏感性分析 |
| `12_figures_tables_npj` | 按 npj 风格整理主文图、补充图、主文表和补充表 |
| `13_manuscript_and_submission` | 存放英文稿、cover letter、highlights、response template 和投稿材料 |

## 推荐主线

主暴露为 `E-DII`，用于代表膳食炎症潜能；`HEI-2015`、`DASH`、`aMED` 作为传统健康膳食质量参照；`hPDI`、`uPDI`、`PHDI` 作为植物性和可持续膳食扩展维度。核心结局应从 alpha diversity 拓展到 beta diversity、dbRDA、属水平差异丰度和生态模块，以增强微生物生态学叙事。

## 主文图建议

1. Figure 1：研究流程图 + 膳食指数相关结构。
2. Figure 2：E-DII 与 alpha diversity / beta diversity 总览。
3. Figure 3：PERMANOVA + PCoA + dbRDA 群落结构结果。
4. Figure 4：核心差异菌热图 + UpSet 图。
5. Figure 5：调整后属水平模型或生态模块 / 网络图。

## 下一步建议

优先补充三类分析：`dbRDA`、`MaAsLin2/ANCOM-BC2`、`生态模块/网络分析`。这三项最能把文章从普通 NHANES 关联研究提升为更适合 `npj Biofilms and Microbiomes` 的微生物生态故事。
