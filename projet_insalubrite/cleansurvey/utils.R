# =============================================================================
# utils.R — Fonctions génériques réutilisables
# Même logique que le cours (apply_var_dictionary / apply_modality_dictionary)
# + fonctions spécifiques déchets/insalubrité
# =============================================================================

pacman::p_load(dplyr, forcats, labelled, readxl, data.table, naniar)

# -----------------------------------------------------------------------------
# 1. DICTIONNAIRE DE VARIABLES
# -----------------------------------------------------------------------------

#' Applique un dictionnaire de variables à un dataframe
#' (renommage, retypage, labellisation, sélection)
#'
#' @param df       data.frame brut
#' @param dict     data.frame avec colonnes :
#'                 var_orig, var_new, label_new, type_new, keep
#' @return data.frame renommé et sélectionné
apply_var_dictionary <- function(df, dict) {

  stopifnot(all(c("var_orig", "var_new", "type_new", "keep") %in% names(dict)))

  # Ne garder que les variables présentes dans le df
  dict <- dict %>% filter(var_orig %in% names(df))

  # 1. Renommage
  rename_map <- setNames(dict$var_orig, dict$var_new)
  df <- df %>% rename(!!!rename_map)

  # 2. Labels Stata
  if ("label_new" %in% names(dict)) {
    label_map <- setNames(dict$label_new, dict$var_new)
    for (v in intersect(names(df), names(label_map))) {
      attr(df[[v]], "label") <- label_map[[v]]
    }
  }

  # 3. Conversion de types
  for (i in seq_len(nrow(dict))) {
    v <- dict$var_new[i]
    t <- tolower(dict$type_new[i])
    if (!v %in% names(df)) next
    if (t == "factor")    df[[v]] <- haven::as_factor(df[[v]], levels = "labels")
    if (t == "numeric")   df[[v]] <- as.numeric(df[[v]])
    if (t == "character") df[[v]] <- as.character(df[[v]])
    if (t == "integer")   df[[v]] <- as.integer(df[[v]])
  }

  # 4. Sélection des variables à conserver
  vars_keep <- dict %>%
    filter(tolower(keep) == "yes") %>%
    pull(var_new)

  df %>% select(any_of(vars_keep))
}

# -----------------------------------------------------------------------------
# 2. DICTIONNAIRE DE MODALITÉS
# -----------------------------------------------------------------------------

#' Recode les modalités des variables facteur
#'
#' @param df    data.frame (après apply_var_dictionary)
#' @param dict  data.frame avec colonnes : var_name, label_init, label_new
#' @return data.frame avec modalités recodées
apply_modality_dictionary <- function(df, dict) {

  vars_to_recode <- intersect(names(df), unique(dict$var_name))

  df %>%
    mutate(
      across(
        all_of(vars_to_recode),
        ~ {
          if (!is.factor(.x)) return(.x)
          d <- dict %>% filter(var_name == cur_column())
          if (nrow(d) == 0) return(.x)
          fct_relabel(.x, function(lvls) {
            idx <- match(lvls, d$label_init)
            ifelse(is.na(idx), lvls, d$label_new[idx])
          })
        }
      )
    )
}

# -----------------------------------------------------------------------------
# 3. NETTOYAGE DES VALEURS ABERRANTES
# -----------------------------------------------------------------------------

#' Remplace par NA les valeurs numériques hors d'un intervalle [min, max]
#'
#' @param df    data.frame
#' @param var   nom de la variable (character)
#' @param min   borne inférieure inclusive
#' @param max   borne supérieure inclusive
#' @param log   si TRUE, affiche un message avec le nombre de remplacements
#' @return data.frame avec les aberrants remplacés par NA
flag_outliers <- function(df, var, min = -Inf, max = Inf, log = TRUE) {
  if (!var %in% names(df)) {
    message("  [flag_outliers] Variable introuvable : ", var)
    return(df)
  }
  n_avant <- sum(!is.na(df[[var]]))
  df[[var]] <- ifelse(df[[var]] < min | df[[var]] > max, NA_real_, df[[var]])
  n_apres <- sum(!is.na(df[[var]]))
  if (log) {
    message(sprintf("  [flag_outliers] %s : %d valeur(s) aberrante(s) → NA",
                    var, n_avant - n_apres))
  }
  df
}

# -----------------------------------------------------------------------------
# 4. CONTRÔLES DE COHÉRENCE
# -----------------------------------------------------------------------------

#' Ajoute une colonne flag_incoh_* = TRUE si une règle est violée
#'
#' @param df          data.frame
#' @param flag_name   nom de la colonne de flag à créer
#' @param condition   expression logique (dplyr-style) qui renvoie TRUE si incohérent
#' @return data.frame avec la colonne flag ajoutée
add_coherence_flag <- function(df, flag_name, condition) {
  df %>% mutate(!!flag_name := {{ condition }})
}

# -----------------------------------------------------------------------------
# 5. TAUX DE COMPLÉTION
# -----------------------------------------------------------------------------

#' Calcule le taux de remplissage de chaque variable
#'
#' @param df data.frame
#' @return data.frame avec var, n_obs, n_missing, taux_na, taux_complete
taux_completion <- function(df) {
  tibble(
    var          = names(df),
    n_obs        = nrow(df),
    n_missing    = sapply(df, function(x) sum(is.na(x))),
    taux_na      = round(n_missing / n_obs, 4),
    taux_complete = round(1 - taux_na, 4)
  ) %>%
    arrange(desc(taux_na))
}

# -----------------------------------------------------------------------------
# 6. AGRÉGATION DES VARIABLES MULTI-CHOIX (_v1..._vN)
# -----------------------------------------------------------------------------

#' Combine des colonnes binaires 0/1 en une colonne texte listant les modalités actives
#'
#' @param df         data.frame
#' @param cols       vecteur des noms de colonnes binaires
#' @param labels     vecteur de labels correspondants (même ordre)
#' @param new_col    nom de la nouvelle colonne texte
#' @return data.frame avec new_col ajoutée
combine_multichoix <- function(df, cols, labels, new_col) {
  stopifnot(length(cols) == length(labels))
  cols_present <- cols[cols %in% names(df)]
  labels_present <- labels[cols %in% names(df)]

  df[[new_col]] <- apply(df[cols_present], 1, function(row) {
    actifs <- labels_present[which(row == 1)]
    if (length(actifs) == 0) NA_character_
    else paste(actifs, collapse = " | ")
  })
  df
}

# -----------------------------------------------------------------------------
# 7. SCORES LIKERT (satisfaction, qualité) → variable ordinale harmonisée
# -----------------------------------------------------------------------------

#' Convertit une variable Likert 4 niveaux en score numérique 1-4
#' et en version binaire satisfait/non-satisfait
#'
#' @param df      data.frame
#' @param var     variable source (factor)
#' @param positifs modalités considérées comme positives (satisfait/bon)
#' @return data.frame avec var_score (1-4) et var_satisfait (0/1)
score_likert <- function(df, var, positifs) {
  score_col   <- paste0(var, "_score")
  satisf_col  <- paste0(var, "_satisfait")
  df[[score_col]]  <- as.numeric(df[[var]])
  df[[satisf_col]] <- as.integer(as.character(df[[var]]) %in% positifs)
  df
}
