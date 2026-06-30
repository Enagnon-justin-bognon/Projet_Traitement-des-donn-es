# =============================================================================
# 4_qaqc / 4_qaqc.R
# Étape 4 : Quality Assurance / Quality Control
#
# Produit un rapport Excel avec :
#   - Feuille 1 : Métadonnées & limites des données
#   - Feuille 2 : Taux de complétion par variable
#   - Feuille 3 : Rapport des incohérences
#   - Feuille 4 : Statistiques descriptives — Ménage & CM
#   - Feuille 5 : Statistiques descriptives — Déchets ménagers
#   - Feuille 6 : Statistiques descriptives — Environnement communautaire
#   - Feuille 7 : Statistiques descriptives — Santé
#   - Feuille 8 : Analyse données manquantes (MCAR/MAR)
#
# Entrée  : output/03_insalubrite_analytique.csv
# Sortie  : output/04_QAQC_insalubrite.xlsx
# =============================================================================

rm(list = ls()); gc()

pacman::p_load(dplyr, readr, openxlsx, naniar, forcats, tidyr, purrr, data.table)

source("cleansurvey/config.R")
source("cleansurvey/utils.R")

# --- Lecture -----------------------------------------------------------------
df <- read_csv(file.path(OUTPUT_PATH, "03_insalubrite_analytique.csv"),
               show_col_types = FALSE)
message(sprintf("[4-QAQC] Table analytique : %d obs × %d var", nrow(df), ncol(df)))

wb <- createWorkbook()

# Styles Excel
style_titre   <- createStyle(fontSize = 12, fontColour = "#FFFFFF",
                              fgFill = "#2E75B6", textDecoration = "Bold",
                              halign = "CENTER", wrapText = TRUE)
style_header  <- createStyle(fontSize = 10, fontColour = "#FFFFFF",
                              fgFill = "#4472C4", textDecoration = "Bold")
style_flag    <- createStyle(fgFill = "#FFE699")
style_rouge   <- createStyle(fgFill = "#FF6B6B", fontColour = "#FFFFFF")
style_vert    <- createStyle(fgFill = "#70AD47", fontColour = "#FFFFFF")

write_sheet <- function(wb, sheet_name, data, titre = NULL) {
  addWorksheet(wb, sheet_name)
  row_start <- 1
  if (!is.null(titre)) {
    writeData(wb, sheet_name, titre, startRow = 1, startCol = 1)
    addStyle(wb, sheet_name, style_titre, rows = 1, cols = 1:ncol(data))
    mergeCells(wb, sheet_name, rows = 1, cols = 1:max(ncol(data), 2))
    row_start <- 3
  }
  writeDataTable(wb, sheet_name, data, startRow = row_start, tableStyle = "TableStyleMedium9")
  setColWidths(wb, sheet_name, cols = 1:ncol(data), widths = "auto")
}

# ============================================================================
# FEUILLE 1 : MÉTADONNÉES ET LIMITES
# ============================================================================
meta_df <- tibble(
  Champ        = c("Fichier source", "N observations", "N variables brutes",
                   "Date de traitement", "Région couverte",
                   "Variables absentes (signalées NA)",
                   "Seuil flag NA utilisé"),
  Valeur       = c(RAW_FILE_NAME, as.character(nrow(df)),
                   "139",
                   as.character(Sys.Date()),
                   "Région de Dakar (zones urbaines/périurbaines — 52 communes)",
                   paste(names(VARIABLES_ABSENTES), collapse = ", "),
                   paste0(SEUIL_NA_FLAG * 100, "%"))
)
write_sheet(wb, "1_Metadonnees", meta_df,
            "Métadonnées et limites de la base Insalubrité 2022-2023")

# ============================================================================
# FEUILLE 1bis : PROBLÈMES DE QUALITÉ DE DONNÉES IDENTIFIÉS
# ============================================================================
dq_path <- file.path(AUX_FILE_PATH, "data_quality_issues.csv")
if (file.exists(dq_path)) {
  dq_df <- read_csv(dq_path, show_col_types = FALSE)
  write_sheet(wb, "1bis_Limites_Donnees", dq_df,
              "Problèmes de qualité identifiés dans le fichier source et stratégie retenue")
}

# ============================================================================
# FEUILLE 2 : TAUX DE COMPLÉTION
# ============================================================================
compl <- taux_completion(df) %>%
  mutate(
    statut = case_when(
      taux_na == 0              ~ "✅ Complet",
      taux_na <= 0.05           ~ "🟢 <5% NA",
      taux_na <= SEUIL_NA_FLAG  ~ "🟡 5-20% NA",
      taux_na <= 0.5            ~ "🟠 20-50% NA",
      TRUE                      ~ "🔴 >50% NA"
    )
  )
write_sheet(wb, "2_Completion", compl,
            "Taux de complétion par variable")

# ============================================================================
# FEUILLE 3 : INCOHÉRENCES
# ============================================================================
if (file.exists(file.path(OUTPUT_PATH, "02_flags_coherence.csv"))) {
  flags_df <- read_csv(file.path(OUTPUT_PATH, "02_flags_coherence.csv"),
                       show_col_types = FALSE)
  write_sheet(wb, "3_Incoherences", flags_df,
              "Contrôles de cohérence — Règles métier")
}

# ============================================================================
# FEUILLE 4 : STATISTIQUES — MÉNAGE ET CM
# ============================================================================
stats_men <- function(df) {
  rows <- list()

  # Taille ménage
  if ("taille_menage" %in% names(df)) {
    rows[["taille_menage"]] <- tibble(
      Variable = "Taille du ménage",
      Statistique = c("Moyenne","Médiane","Min","Max","% NA"),
      Valeur = c(
        round(mean(df$taille_menage, na.rm = TRUE), 2),
        median(df$taille_menage, na.rm = TRUE),
        min(df$taille_menage, na.rm = TRUE),
        max(df$taille_menage, na.rm = TRUE),
        round(mean(is.na(df$taille_menage)) * 100, 1)
      )
    )
  }

  # Âge CM
  if ("age_cm" %in% names(df)) {
    rows[["age_cm"]] <- tibble(
      Variable = "Âge du Chef de ménage",
      Statistique = c("Moyenne","Médiane","Min","Max","% NA"),
      Valeur = c(
        round(mean(df$age_cm, na.rm = TRUE), 1),
        median(df$age_cm, na.rm = TRUE),
        min(df$age_cm, na.rm = TRUE),
        max(df$age_cm, na.rm = TRUE),
        round(mean(is.na(df$age_cm)) * 100, 1)
      )
    )
  }

  bind_rows(rows)
}

vars_cat_men <- c("sexe_cm", "niveau_instruction_cm", "alphabetise_cm",
                  "type_logement", "statut_occupation", "milieu")

freqs_men <- map_dfr(vars_cat_men, function(v) {
  if (!v %in% names(df)) return(NULL)
  df %>%
    count(!!sym(v), name = "n") %>%
    mutate(pct = round(100 * n / sum(n), 1),
           Variable = v) %>%
    rename(Modalite = 1) %>%
    select(Variable, Modalite, n, pct)
})

stats_num_men <- stats_men(df)

write_sheet(wb, "4_Stats_Menage_CM",
            bind_rows(
              stats_num_men %>% mutate(across(everything(), as.character)),
              tibble(Variable = "---", Statistique = "VARIABLES CATÉGORIELLES", Valeur = ""),
              freqs_men %>% rename(Statistique = Modalite, Valeur = n) %>%
                mutate(Valeur = as.character(Valeur), pct = as.character(pct)) %>%
                select(Variable, Statistique, Valeur)
            ),
            "Statistiques descriptives — Ménage & Chef de ménage")

# ============================================================================
# FEUILLE 5 : STATISTIQUES — DÉCHETS MÉNAGERS
# ============================================================================
vars_dechets <- c("mode_evacuation_principal", "pratique_tri", "pratique_revente",
                  "traite_en_autonomie", "acces_service_public", "acces_service_prive",
                  "consent_payer", "qualite_conteneur_ferme",
                  "satisfaction_collecte", "freq_collecte")

stats_dechets <- map_dfr(vars_dechets, function(v) {
  if (!v %in% names(df)) return(NULL)
  x <- df[[v]]
  if (is.numeric(x)) {
    tibble(Variable = v,
           Modalite = c("Moyenne","Médiane","% NA"),
           n        = c(round(mean(x, na.rm=TRUE),2),
                        median(x, na.rm=TRUE),
                        round(mean(is.na(x))*100,1)),
           pct      = NA_real_)
  } else {
    df %>% count(!!sym(v), name = "n") %>%
      mutate(pct = round(100 * n / sum(n), 1),
             Variable = v) %>%
      rename(Modalite = 1) %>%
      select(Variable, Modalite, n, pct)
  }
})

# Montant mensuel
if ("montant_mensuel_fcfa" %in% names(df)) {
  stats_montant <- tibble(
    Variable = "montant_mensuel_fcfa (proxy FCFA)",
    Modalite = c("Moyenne","Médiane","% ménages avec montant > 0"),
    n        = c(round(mean(df$montant_mensuel_fcfa, na.rm=TRUE), 0),
                 median(df$montant_mensuel_fcfa, na.rm=TRUE),
                 round(mean(df$montant_mensuel_fcfa > 0, na.rm=TRUE)*100, 1)),
    pct      = NA_real_
  )
  stats_dechets <- bind_rows(stats_dechets, stats_montant)
}

write_sheet(wb, "5_Stats_Dechets", stats_dechets,
            "Statistiques descriptives — Gestion des déchets ménagers")

# ============================================================================
# FEUILLE 6 : STATISTIQUES — ENVIRONNEMENT COMMUNAUTAIRE
# ============================================================================
vars_env <- c("freq_depots_sauvages", "freq_eaux_usees_rue", "presence_nuisibles",
              "satisfaction_bacs", "qualite_balayage", "connaissance_ucg",
              "salubrite_quartier_cat", "score_salubrite_quartier")

stats_env <- map_dfr(vars_env, function(v) {
  if (!v %in% names(df)) return(NULL)
  x <- df[[v]]
  if (is.numeric(x)) {
    tibble(Variable = v,
           Modalite = c("Moyenne","Médiane","% NA"),
           n        = c(round(mean(x,na.rm=TRUE),2),
                        median(x,na.rm=TRUE),
                        round(mean(is.na(x))*100,1)),
           pct = NA_real_)
  } else {
    df %>% count(!!sym(v), name = "n") %>%
      mutate(pct = round(100*n/sum(n),1), Variable = v) %>%
      rename(Modalite = 1) %>% select(Variable, Modalite, n, pct)
  }
})
write_sheet(wb, "6_Stats_Environnement", stats_env,
            "Statistiques descriptives — Environnement & communauté")

# ============================================================================
# FEUILLE 7 : STATISTIQUES — SANTÉ
# ============================================================================
mal_vars <- c("mal_fievre","mal_asthme","mal_toux","mal_sinusite",
              "mal_nausees","mal_demangeaisons","mal_rhume")
stats_sante <- map_dfr(intersect(mal_vars, names(df)), function(v) {
  n_oui <- sum(df[[v]] == 1, na.rm = TRUE)
  tibble(
    Maladie     = v,
    N_declares  = n_oui,
    Pct_declares = round(100 * n_oui / nrow(df), 1),
    N_NA         = sum(is.na(df[[v]]))
  )
})

if ("nb_maladies_declarees" %in% names(df)) {
  resume_sante <- tibble(
    Indicateur = c("Ménages avec ≥1 maladie déclarée (%)",
                   "Nb moyen maladies par ménage",
                   "Ménages avec maladie respiratoire (%)"),
    Valeur = c(
      round(mean(df$menage_malade == "Oui", na.rm = TRUE)*100, 1),
      round(mean(df$nb_maladies_declarees, na.rm = TRUE), 2),
      if ("maladie_respiratoire" %in% names(df))
        round(mean(df$maladie_respiratoire == 1, na.rm = TRUE)*100, 1)
      else NA
    )
  )
  addWorksheet(wb, "7_Stats_Sante")
  writeDataTable(wb, "7_Stats_Sante", resume_sante, startRow = 2,
                 tableStyle = "TableStyleMedium9")
  writeData(wb, "7_Stats_Sante",
            "Statistiques sanitaires — Maladies liées à l'insalubrité (12 derniers mois)",
            startRow = 1)
  writeDataTable(wb, "7_Stats_Sante", stats_sante, startRow = nrow(resume_sante) + 5,
                 tableStyle = "TableStyleLight11")
  setColWidths(wb, "7_Stats_Sante", cols = 1:4, widths = "auto")
}

# ============================================================================
# FEUILLE 8 : ANALYSE DONNÉES MANQUANTES
# ============================================================================
# Résumé MCAR/MAR pour les variables avec NA > 5%
vars_na <- compl %>% filter(taux_na > 0.05) %>% pull(var)
vars_na_present <- intersect(vars_na, names(df))

if (length(vars_na_present) > 0) {
  pattern_na <- df %>%
    select(all_of(vars_na_present)) %>%
    mutate(across(everything(), is.na)) %>%
    group_by(across(everything())) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(desc(n)) %>%
    mutate(pct = round(100 * n / nrow(df), 1))

  write_sheet(wb, "8_Analyse_NA", pattern_na,
              "Patterns de données manquantes (base pour test MCAR/MAR)")

  # Note méthodologique
  note <- tibble(
    Note = c(
      "Pour tester MCAR : utiliser TestMCARNormality() (package BaylorEdPsych) sur les variables numériques.",
      "Pour tester MAR : régresser is.na(var) ~ variables de contexte (logit).",
      "Si MNAR confirmé : préférer une imputation multiple (MICE) ou signaler comme limite.",
      "Les variables absentes (dépenses, actifs, emploi CM) sont MNAR par construction (non collectées)."
    )
  )
  writeData(wb, "8_Analyse_NA", note,
            startRow = nrow(pattern_na) + 6)
}

# ============================================================================
# SAUVEGARDE
# ============================================================================
qaqc_path <- file.path(OUTPUT_PATH, "04_QAQC_insalubrite.xlsx")
saveWorkbook(wb, qaqc_path, overwrite = TRUE)
message(sprintf("\n✅ [Étape 4 terminée] → 04_QAQC_insalubrite.xlsx sauvegardé"))
message("   8 feuilles : Métadonnées | Complétion | Incohérences | Ménage/CM |")
message("               Déchets | Environnement | Santé | Analyse NA")
