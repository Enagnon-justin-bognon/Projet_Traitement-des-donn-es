# =============================================================================
# Requirements.R — Installation de tous les packages du pipeline
# Exécuter UNE SEULE FOIS avant le premier lancement
# =============================================================================

if (!require("pacman")) install.packages("pacman")

pacman::p_load(
  # Lecture données
  haven,          # read_dta (.dta Stata)
  readxl,         # read_excel (dictionnaires)
  readr,          # read_csv

  # Manipulation
  dplyr,
  tidyr,
  purrr,
  forcats,
  tibble,
  data.table,     # fwrite (sauvegarde rapide)

  # Labels Stata
  labelled,

  # Données manquantes
  naniar,         # vis_miss, gg_miss_var
  VIM,            # aggr (patterns de NA)
  mice,           # imputation multiple

  # Test MCAR
  # BaylorEdPsych, # TestMCARNormality — installer séparément si besoin
  # install.packages("BaylorEdPsych")

  # Rapport Excel
  openxlsx,

  # Modélisation (QAQC — logit non-réponse)
  stats           # glm (inclus dans base R)
)

message("✅ Tous les packages chargés")
