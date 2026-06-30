# =============================================================================
# 1_dictionary / 1_apply_dict.R
# Étape 1 : Application du dictionnaire rempli → renommage, typage, sélection
#
# Entrée  : input/22_23_Insalubrite.dta
#           dictionaries/dictionary_insalubrite_filled.xlsx  (rempli manuellement)
# Sortie  : output/01_insalubrite_labeled.csv
#           dictionaries/dictionary_modality_init.csv  (à compléter)
# =============================================================================

rm(list = ls()); gc()

pacman::p_load(haven, readxl, dplyr, purrr, tibble, data.table)

source("cleansurvey/config.R")
source("cleansurvey/utils.R")

# --- 1. Lecture données brutes -----------------------------------------------
df_raw <- read_dta(file.path(MAIN_DATA_PATH, RAW_FILE_NAME))
message(sprintf("[1] Données brutes : %d obs × %d var", nrow(df_raw), ncol(df_raw)))

# --- 2. Lecture du dictionnaire rempli ---------------------------------------
dict_path <- file.path(AUX_FILE_PATH, "dictionary_insalubrite_filled.xlsx")
if (!file.exists(dict_path)) {
  stop("❌ dictionary_insalubrite_filled.xlsx introuvable.\n",
       "   → Compléter dictionary_insalubrite_init.csv et le sauvegarder en .xlsx")
}

dict_filled <- read_excel(dict_path) %>%
  mutate(across(c(keep, type_new), tolower))

# --- 3. Vérification alignement init / filled --------------------------------
dict_init <- read_csv(file.path(AUX_FILE_PATH, "dictionary_insalubrite_init.csv"),
                      show_col_types = FALSE)
diff_vars <- setdiff(dict_init$var_orig, dict_filled$var_orig)
if (length(diff_vars) > 0) {
  warning("⚠️  Variables du fichier brut absentes du dictionnaire rempli :\n  ",
          paste(diff_vars, collapse = ", "))
}

# --- 4. Application du dictionnaire ------------------------------------------
df_labeled <- apply_var_dictionary(df_raw, dict_filled)
message(sprintf("[1] Après dictionnaire : %d obs × %d var",
                nrow(df_labeled), ncol(df_labeled)))

# --- 5. Extraction des modalités pour dictionnaire de modalités --------------
mod_dict_init <- map_dfr(names(df_labeled), function(v) {
  x <- df_labeled[[v]]
  if (is.factor(x) && length(levels(x)) > 0) {
    tibble(var_name = v, label_init = levels(x), label_new = NA_character_)
  }
})

fwrite(mod_dict_init,
       file.path(AUX_FILE_PATH, "dictionary_modality_init.csv"))

# --- 6. Sauvegarde intermédiaire ---------------------------------------------
fwrite(df_labeled, file.path(OUTPUT_PATH, "01_insalubrite_labeled.csv"))

message("✅ [Étape 1 terminée]")
message("   → 01_insalubrite_labeled.csv sauvegardé")
message("   → dictionary_modality_init.csv sauvegardé → à compléter si nécessaire")
message("   → Prochaine étape : cleansurvey/2_clean/2_clean.R")
