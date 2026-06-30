# =============================================================================
# 0_setup / 0_get_dict.R
# Étape 0 : Génération automatique du dictionnaire brut des variables
#
# ➜ À exécuter UNE SEULE FOIS (ou à chaque nouvelle édition de l'enquête).
# ➜ Produit : dictionaries/dictionary_insalubrite_init.csv
#             dictionaries/commune_milieu_init.csv
#
# Après exécution, compléter manuellement :
#   - dictionary_insalubrite_init.csv → copier en _filled.xlsx
#     et remplir : var_new, label_new, type_new, keep, module, notes
#   - commune_milieu_init.csv → remplir la colonne milieu (urbain/périurbain)
# =============================================================================

rm(list = ls()); gc()

pacman::p_load(haven, tibble, dplyr, labelled, data.table, readr)

source("cleansurvey/config.R")

# --- Garde-fou : ne pas écraser un dictionnaire déjà complété ----------------
filled_path <- file.path(AUX_FILE_PATH, "dictionary_insalubrite_filled.xlsx")
if (file.exists(filled_path)) {
  message("⚠️  dictionary_insalubrite_filled.xlsx existe déjà.")
  message("   Ce script régénère uniquement le fichier _init.csv (référence brute).")
  message("   Le fichier _filled.xlsx ne sera PAS modifié.")
}

# --- Lecture du fichier brut -------------------------------------------------
df <- read_dta(file.path(MAIN_DATA_PATH, RAW_FILE_NAME))
message(sprintf("Fichier lu : %d observations × %d variables", nrow(df), ncol(df)))

# --- Construction du dictionnaire initial ------------------------------------
dict_init <- tibble(
  var_orig   = names(df),
  label_orig = sapply(df, function(x) {
    lbl <- var_label(x)
    if (!is.null(lbl) && nzchar(lbl)) lbl else NA_character_
  }),
  type_orig  = sapply(df, function(x) {
    if (inherits(x, "haven_labelled")) "labelled"
    else if (is.factor(x))            "factor"
    else if (is.character(x))         "character"
    else if (is.numeric(x))           "numeric"
    else class(x)[1]
  }),
  n_distinct = sapply(df, function(x) n_distinct(x, na.rm = TRUE)),
  n_missing  = sapply(df, function(x) sum(is.na(x))),
  taux_na    = round(sapply(df, function(x) mean(is.na(x))), 4),
  # Colonnes à remplir manuellement
  module     = NA_character_,   # I, II, III, IV, derive
  var_new    = NA_character_,   # nouveau nom snake_case
  label_new  = NA_character_,   # label français clair
  type_new   = NA_character_,   # factor | numeric | character | integer
  keep       = NA_character_    # yes | no
)

fwrite(dict_init,
       file.path(AUX_FILE_PATH, "dictionary_insalubrite_init.csv"))
message("✅ dictionary_insalubrite_init.csv sauvegardé → à compléter manuellement")

# --- Table commune → milieu de résidence (à compléter manuellement) ----------
communes_df <- df %>%
  count(Commune, name = "n_menages") %>%
  mutate(
    milieu = NA_character_  # À remplir : "urbain" ou "périurbain"
  )

# Ajout du label de commune depuis les value labels
val_labs <- attr(df$Commune, "labels")
if (!is.null(val_labs)) {
  communes_df <- communes_df %>%
    mutate(commune_label = val_labs[match(Commune, val_labs)])
}

fwrite(communes_df,
       file.path(AUX_FILE_PATH, "commune_milieu_init.csv"))
message("✅ commune_milieu_init.csv sauvegardé → remplir colonne 'milieu'")
message("   (urbain / périurbain pour chacune des ", nrow(communes_df), " communes)")

message("\n📋 Prochaine étape :")
message("   1. Ouvrir dictionaries/dictionary_insalubrite_init.csv")
message("   2. Copier en dictionary_insalubrite_filled.xlsx")
message("   3. Remplir : module, var_new, label_new, type_new, keep")
message("   4. Remplir commune_milieu_init.csv → colonne 'milieu'")
message("   5. Lancer : cleansurvey/1_dictionary/1_apply_dict.R")
