# =============================================================================
# run_all.R — Pipeline maître Insalubrité
#
# Usage : Rscript --vanilla run_all.R
#         ou source("run_all.R") depuis RStudio
#
# Ce script exécute les étapes dans l'ordre.
# Pour une nouvelle édition de l'enquête :
#   1. Mettre le nouveau .dta dans input/
#   2. Modifier RAW_FILE_NAME dans cleansurvey/config.R
#   3. Compléter les dictionnaires dans dictionaries/
#   4. Relancer run_all.R
# =============================================================================

pacman::p_load(stringr, here)

message("=" %+% strrep("=", 59))
message("  PIPELINE INSALUBRITÉ — GESTION DES DÉCHETS SOLIDES MÉNAGERS")
message("  Sénégal — Enquête 2022-2023")
message("=" %+% strrep("=", 59), "\n")

# Ordre des étapes
# L'étape 0 (get_dict) est commentée : à exécuter UNE SEULE FOIS
# puis décommenter manuellement après complétion des dictionnaires

etapes <- c(
  # "cleansurvey/0_setup/0_get_dict.R",       # ← décommenter pour la 1ère fois
  "cleansurvey/1_dictionary/1_apply_dict.R",
  "cleansurvey/2_clean/2_clean.R",
  "cleansurvey/3_derive/3_derive.R",
  "cleansurvey/4_qaqc/4_qaqc.R"
)

# Vérification des fichiers requis
stopifnot("input/" = dir.exists("input"))
stopifnot("output/" = dir.exists("output"))
stopifnot("dictionaries/" = dir.exists("dictionaries"))

t_debut <- Sys.time()

for (s in etapes) {
  message("\n", strrep("-", 60))
  message("▶  ", s)
  message(strrep("-", 60))
  tryCatch(
    source(s),
    error = function(e) {
      message("❌ ERREUR dans : ", s)
      message("   ", conditionMessage(e))
      stop("Pipeline interrompu. Corriger l'erreur ci-dessus et relancer.")
    }
  )
  message("✅ ", s, " — OK")
}

t_fin <- Sys.time()
message("\n", strrep("=", 60))
message("  PIPELINE TERMINÉ en ", round(difftime(t_fin, t_debut, units="secs"), 1), " s")
message("  Outputs dans : output/")
message("    01_insalubrite_labeled.csv      ← après renommage/typage")
message("    02_insalubrite_clean.csv        ← après nettoyage")
message("    02_flags_coherence.csv          ← rapport incohérences")
message("    02_taux_completion.csv          ← taux de NA par variable")
message("    03_insalubrite_analytique.csv   ← TABLE FINALE (variables dérivées)")
message("    04_QAQC_insalubrite.xlsx        ← rapport QAQC complet (8 feuilles)")
message(strrep("=", 60))
