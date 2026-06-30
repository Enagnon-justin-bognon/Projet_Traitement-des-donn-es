# =============================================================================
# 2_clean / 2_clean.R
# Étape 2 : Nettoyage — aberrants, manquants, cohérence, variables "other"
#
# Entrée  : output/01_insalubrite_labeled.csv
# Sortie  : output/02_insalubrite_clean.csv
#           output/02_flags_coherence.csv   (rapport des incohérences)
# =============================================================================

rm(list = ls()); gc()

pacman::p_load(dplyr, readr, naniar, mice, forcats, data.table)

source("cleansurvey/config.R")
source("cleansurvey/utils.R")

# --- 1. Lecture -----------------------------------------------------------
df <- read_csv(file.path(OUTPUT_PATH, "01_insalubrite_labeled.csv"),
               show_col_types = FALSE)
message(sprintf("[2] Chargement : %d obs × %d var", nrow(df), ncol(df)))

# ============================================================================
# A. TRAITEMENT DES VALEURS ABERRANTES
# ============================================================================
message("\n[2-A] Traitement des valeurs aberrantes")

# Âge du répondant
if ("age_repondant" %in% names(df)) {
  df <- flag_outliers(df, "age_repondant", min = AGE_REP_MIN, max = AGE_REP_MAX)
}

# Âge du chef de ménage
if ("age_cm" %in% names(df)) {
  df <- flag_outliers(df, "age_cm", min = AGE_CM_MIN, max = AGE_CM_MAX)
}

# Taille du ménage (somme enfants <5 + enfants 5-15 + hommes 15+ + femmes 15+)
if (all(c("nb_enf_moins5", "nb_enf_5_15", "nb_hom_15plus", "nb_fem_15plus") %in% names(df))) {
  df <- df %>%
    mutate(taille_menage = nb_enf_moins5 + nb_enf_5_15 + nb_hom_15plus + nb_fem_15plus)
  df <- flag_outliers(df, "taille_menage", min = 1, max = TAILLE_MEN_MAX)
}

# Durée de résidence (en mois) : valeurs négatives ou extrêmes
if ("duree_residence_mois" %in% names(df)) {
  df <- flag_outliers(df, "duree_residence_mois", min = 0, max = 1200)  # max = 100 ans
}

# ============================================================================
# B. TRAITEMENT DES VARIABLES "OTHER" (texte libre)
# ============================================================================
message("\n[2-B] Traitement des variables 'other'")
# Les variables _other sont des champs texte libres issus de Kobo.
# Stratégie : harmonisation basique (trim, lowercase), pas d'imputation.
other_vars <- grep("_other$", names(df), value = TRUE)
message(sprintf("  Variables _other détectées : %d", length(other_vars)))
for (v in other_vars) {
  df[[v]] <- trimws(tolower(df[[v]]))
  df[[v]] <- na_if(df[[v]], "")
  df[[v]] <- na_if(df[[v]], "na")
}

# ============================================================================
# C. CONTRÔLES DE COHÉRENCE
# ============================================================================
message("\n[2-C] Contrôles de cohérence")
flags_list <- list()

# Règle 1 : Si II_7 (tri des déchets) = Non → II_8 (revente) devrait être Non
# (on ne peut pas revendre sans trier)
if (all(c("pratique_tri", "pratique_revente") %in% names(df))) {
  df <- add_coherence_flag(
    df, "flag_tri_revente",
    pratique_tri == "Non" & pratique_revente == "Oui"
  )
  flags_list[["flag_tri_revente"]] <- "Revente déclarée sans tri préalable"
}

# Règle 2 : Satisfaction service de collecte alors que II_13 = Non (pas accès benne)
if (all(c("acces_benne_tasseuse", "satisfaction_collecte") %in% names(df))) {
  df <- add_coherence_flag(
    df, "flag_satisf_sans_acces",
    acces_benne_tasseuse == "Non" & !is.na(satisfaction_collecte)
  )
  flags_list[["flag_satisf_sans_acces"]] <- "Satisfaction collecte évaluée sans accès benne"
}

# Règle 3 : II_25_1 (montant payé) renseigné alors que II_24 = Non (service gratuit)
if (all(c("service_payant", "montant_service") %in% names(df))) {
  df <- add_coherence_flag(
    df, "flag_montant_gratuit",
    service_payant == "Non" & !is.na(montant_service)
  )
  flags_list[["flag_montant_gratuit"]] <- "Montant renseigné malgré service déclaré gratuit"
}

# Règle 4 : Âge CM < 18 ans
if ("age_cm" %in% names(df)) {
  df <- add_coherence_flag(
    df, "flag_age_cm_mineur",
    !is.na(age_cm) & age_cm < 18
  )
  flags_list[["flag_age_cm_mineur"]] <- "Chef de ménage mineur (<18 ans)"
}

# Règle 5 : nb membres négatif
if ("taille_menage" %in% names(df)) {
  df <- add_coherence_flag(
    df, "flag_taille_neg",
    !is.na(taille_menage) & taille_menage < 1
  )
  flags_list[["flag_taille_neg"]] <- "Taille ménage nulle ou négative"
}

# Rapport des flags
flag_cols <- names(flags_list)
rapport_flags <- map_dfr(flag_cols, function(f) {
  n <- if (f %in% names(df)) sum(df[[f]], na.rm = TRUE) else 0
  tibble(flag = f, description = flags_list[[f]], n_cas = n,
         pct = round(100 * n / nrow(df), 2))
})
message("\n  Résumé des incohérences détectées :")
print(rapport_flags)
fwrite(rapport_flags, file.path(OUTPUT_PATH, "02_flags_coherence.csv"))

# ============================================================================
# D. ANALYSE ET TRAITEMENT DES VALEURS MANQUANTES
# ============================================================================
message("\n[2-D] Analyse des données manquantes")

# Taux de NA par variable
compl <- taux_completion(df %>% select(-any_of(other_vars), -any_of(flag_cols)))
vars_haute_na <- compl %>% filter(taux_na > SEUIL_NA_FLAG)
message(sprintf("  Variables avec >%d%% de NA : %d",
                as.integer(SEUIL_NA_FLAG * 100), nrow(vars_haute_na)))
if (nrow(vars_haute_na) > 0) print(vars_haute_na)

fwrite(compl, file.path(OUTPUT_PATH, "02_taux_completion.csv"))

# ============================================================================
# E. IMPUTATION
# ============================================================================
# Stratégie : imputation simple pour les variables numériques clés (médiane)
# Les variables catégorielles : mode (valeur la plus fréquente)
# MCAR / MAR : diagnostiqué dans le QAQC (étape 4)
message("\n[2-E] Imputation des données manquantes")

# Variables numériques — imputation par médiane
vars_num_imputer <- c("age_repondant", "age_cm", "taille_menage")
vars_num_imputer <- intersect(vars_num_imputer, names(df))

for (v in vars_num_imputer) {
  med <- median(df[[v]], na.rm = TRUE)
  n_imp <- sum(is.na(df[[v]]))
  if (n_imp > 0) {
    df[[paste0(v, "_imputed")]] <- ifelse(is.na(df[[v]]), med, df[[v]])
    message(sprintf("  %s : %d NA imputés par médiane (%.1f)", v, n_imp, med))
  }
}

# Variables catégorielles clés — imputation par mode (si NA < 20%)
vars_cat_imputer <- c("sexe_cm", "niveau_instruction_cm", "type_logement",
                      "statut_occupation")
vars_cat_imputer <- intersect(vars_cat_imputer, names(df))

mode_val <- function(x) {
  tab <- sort(table(x, useNA = "no"), decreasing = TRUE)
  if (length(tab) == 0) return(NA)
  names(tab)[1]
}

for (v in vars_cat_imputer) {
  taux <- mean(is.na(df[[v]]))
  if (taux > 0 && taux <= SEUIL_NA_FLAG) {
    mod <- mode_val(df[[v]])
    n_imp <- sum(is.na(df[[v]]))
    df[[v]] <- ifelse(is.na(df[[v]]), mod, as.character(df[[v]]))
    df[[v]] <- as.factor(df[[v]])
    message(sprintf("  %s : %d NA imputés par mode ('%s')", v, n_imp, mod))
  }
}

# ============================================================================
# F. SAUVEGARDE
# ============================================================================
fwrite(df, file.path(OUTPUT_PATH, "02_insalubrite_clean.csv"))
message(sprintf("\n✅ [Étape 2 terminée] → 02_insalubrite_clean.csv (%d obs × %d var)",
                nrow(df), ncol(df)))
message("   → 02_flags_coherence.csv")
message("   → 02_taux_completion.csv")
message("   → Prochaine étape : cleansurvey/3_derive/3_derive.R")
