# =============================================================================
# 3_derive / 3_derive.R
# Étape 3 : Construction des variables dérivées analytiques
#
# C'est ici que l'on construit les variables demandées dans l'énoncé
# à partir de combinaisons de variables collectées.
#
# Entrée  : output/02_insalubrite_clean.csv
#           dictionaries/commune_milieu_filled.csv  (rempli manuellement)
# Sortie  : output/03_insalubrite_analytique.csv  (table finale consolidée)
# =============================================================================

rm(list = ls()); gc()

pacman::p_load(dplyr, readr, forcats, data.table)

source("cleansurvey/config.R")
source("cleansurvey/utils.R")

# --- Lecture -----------------------------------------------------------------
df <- read_csv(file.path(OUTPUT_PATH, "02_insalubrite_clean.csv"),
               show_col_types = FALSE)
message(sprintf("[3] Chargement : %d obs × %d var", nrow(df), ncol(df)))

# ============================================================================
# MODULE I — CARACTÉRISTIQUES DU MÉNAGE ET DU CM
# ============================================================================
message("\n[3-I] Variables ménage & CM")

# --- I.0 Nettoyage des codes résiduels non documentés ------------------------
# Certaines variables (ex: acces_benne_tasseuse / II_13) présentent des codes
# numériques (3,4,5,6) en dehors du dictionnaire Stata original ({1=Oui, 2=Non}).
# Ce sont des résidus de saisie Kobo non documentés dans l'export .dta.
# Stratégie : ces codes sont mis à NA (non interprétables avec certitude),
# et comptabilisés dans le rapport QAQC comme limite de données.
if ("acces_benne_tasseuse" %in% names(df)) {
  n_residuel <- sum(!df$acces_benne_tasseuse %in% c("Oui", "Non") &
                     !is.na(df$acces_benne_tasseuse))
  if (n_residuel > 0) {
    message(sprintf("  ⚠️  acces_benne_tasseuse : %d code(s) résiduel(s) non documenté(s) → NA",
                    n_residuel))
    df$acces_benne_tasseuse <- ifelse(
      df$acces_benne_tasseuse %in% c("Oui", "Non"),
      df$acces_benne_tasseuse, NA
    )
    df$acces_benne_tasseuse <- factor(df$acces_benne_tasseuse, levels = c("Oui", "Non"))
  }
}

# --- I.1 Milieu de résidence -------------------------------------------------
# Source : jointure avec commune_milieu_filled.csv (rempli manuellement)
milieu_path <- file.path(AUX_FILE_PATH, "commune_milieu_filled.csv")
if (file.exists(milieu_path)) {
  commune_milieu <- read_csv(milieu_path, show_col_types = FALSE) %>%
    select(Commune, milieu)
  df <- df %>% left_join(commune_milieu, by = "Commune")
  message("  ✓ milieu_residence joint depuis commune_milieu_filled.csv")
} else {
  df$milieu_residence <- NA_character_
  warning("⚠️  commune_milieu_filled.csv absent — milieu_residence = NA\n",
          "    Remplir dictionaries/commune_milieu_init.csv et sauvegarder en _filled.csv")
}

# --- I.2 Alphabétisation du CM (combinaison de I_12_1 à I_12_5) -------------
# Le CM est alphabétisé s'il lit/écrit dans AU MOINS UNE langue
alph_cols <- c("alpha_francais", "alpha_anglais", "alpha_arabe",
                "alpha_langue_nat", "alpha_autre_langue")
alph_cols_present <- intersect(alph_cols, names(df))
if (length(alph_cols_present) > 0) {
  df <- df %>%
    mutate(
      alpha_cm_score = rowSums(
        across(all_of(alph_cols_present), ~ as.integer(. == "Oui")),
        na.rm = TRUE
      ),
      alphabetise_cm = factor(
        ifelse(alpha_cm_score >= 1, "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ alphabetise_cm construit (score sur ", length(alph_cols_present), " langues)")
}

# --- I.3 Taille et composition du ménage -------------------------------------
if (all(c("nb_enf_moins5", "nb_enf_5_15", "nb_hom_15plus", "nb_fem_15plus") %in% names(df))) {
  df <- df %>%
    mutate(
      taille_menage    = nb_enf_moins5 + nb_enf_5_15 + nb_hom_15plus + nb_fem_15plus,
      nb_adultes       = nb_hom_15plus + nb_fem_15plus,
      nb_enfants_total = nb_enf_moins5 + nb_enf_5_15,
      ratio_dep        = round(nb_enfants_total / pmax(nb_adultes, 1), 2)  # ratio dépendance
    )
  message("  ✓ taille_menage, nb_adultes, nb_enfants_total, ratio_dep")
}

# --- I.4 Variables absentes de la base (à documenter dans le rapport) --------
# Dépenses du ménage, actifs, statut/secteur/revenu CM : non collectés
for (var in names(VARIABLES_ABSENTES)) {
  df[[var]] <- NA_real_
}
message("  ℹ️  Variables non disponibles initialisées à NA :")
message("    ", paste(names(VARIABLES_ABSENTES), collapse = ", "))

# ============================================================================
# MODULE II — DÉCHETS MÉNAGERS : VARIABLES DÉRIVÉES
# ============================================================================
message("\n[3-II] Variables déchets ménagers")

# --- II.1 Sources des déchets (multi-choix → texte combiné) -----------------
# Les colonnes _v1.._v7 ont déjà été renommées en src_* par le dictionnaire (étape 1)
src_cols_renom <- paste0("src_", c("alim","foyer","elevage","animal",
                                    "entretien","commerce","autre"))
src_labels <- c("Consommation alimentaire", "Gestion foyer",
                "Élevage", "Animaux domestiques",
                "Entretien logement", "Commerce/production", "Autre")
df <- combine_multichoix(df,
  cols   = intersect(src_cols_renom, names(df)),
  labels = src_labels[src_cols_renom %in% names(df)],
  new_col = "sources_dechets_txt"
)
message("  ✓ sources_dechets_txt")

# --- II.2 Nature des déchets (multi-choix) -----------------------------------
nat_cols   <- paste0("nat_", c("plastique","papier_carton","restes_alim",
                                "vetements","electromenager","dechets_verts",
                                "metal","excrements","medicaments","autre"))
nat_labels <- c("Plastiques","Papier/Carton","Restes d'aliments","Vêtements",
                "Déchets électroménagers","Déchets verts","Métal",
                "Excréments d'animaux","Médicaments","Autre")
df <- combine_multichoix(df,
  cols    = intersect(nat_cols, names(df)),
  labels  = nat_labels[nat_cols %in% names(df)],
  new_col = "nature_dechets_txt"
)
# Flag déchets dangereux (médicaments ou électroménager présents)
if (all(c("nat_electromenager", "nat_medicaments") %in% names(df))) {
  df <- df %>%
    mutate(presence_dechets_dangereux = as.integer(
      nat_electromenager == 1 | nat_medicaments == 1
    ))
}
message("  ✓ nature_dechets_txt, presence_dechets_dangereux")

# --- II.3 Score d'autonomie de traitement ------------------------------------
# Combine II_12_1 (enfouissement), _2 (incinération), _3 (recyclage), _4 (compostage)
# Score : nb de pratiques appliquées (min 0, max 4)
trt_cols <- c("pratique_enfouissement", "pratique_incineration",
              "pratique_recyclage",     "pratique_compostage")
trt_cols_present <- intersect(trt_cols, names(df))
if (length(trt_cols_present) > 0) {
  df <- df %>%
    mutate(
      score_autonomie_traitement = rowSums(
        across(all_of(trt_cols_present),
               ~ as.integer(. %in% c("Oui la totalité", "Oui une partie"))),
        na.rm = TRUE
      ),
      traite_en_autonomie = factor(
        ifelse(score_autonomie_traitement > 0, "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ score_autonomie_traitement, traite_en_autonomie")
}

# --- II.4 Mode d'évacuation principal ----------------------------------------
# Hiérarchie : benne tasseuse (public) > autre service > autonomie > dépôt sauvage
if ("acces_benne_tasseuse" %in% names(df)) {
  df <- df %>%
    mutate(
      mode_evacuation_principal = case_when(
        acces_benne_tasseuse == "Oui" ~ "Collecte municipale (benne)",
        # service_alternatif est un code Kobo brut ('1','2','3','other')
        # Une cellule vide "" ou NA signifie qu'aucun service alternatif n'a été renseigné
        !is.na(service_alternatif) & trimws(service_alternatif) != "" ~ "Service alternatif (privé/ONG)",
        traite_en_autonomie == "Oui"  ~ "Traitement autonome",
        TRUE                          ~ "Dépôt non contrôlé / autre"
      ),
      mode_evacuation_principal = factor(mode_evacuation_principal)
    )
  message("  ✓ mode_evacuation_principal")
}

# --- II.5 Consentement à payer -----------------------------------------------
# II_24 = "Le service est-il payant ?" + II_25_1 (montant)
# Consentement à payer = Oui si service payant ET montant > 0
# (si gratuit, montant = 0 FCFA par convention)
if (all(c("service_payant", "montant_service") %in% names(df))) {
  df <- df %>%
    mutate(
      montant_mensuel_fcfa = case_when(
        service_payant == "Non" ~ 0,
        montant_service == "Moins de 200 FCFA"        ~ 100,  # point médian
        montant_service == "Entre 200 et 400 FCFA"    ~ 300,
        montant_service == "Entre 401 et 1000 FCFA"   ~ 700,
        montant_service == "Entre 1001 et 2000 FCFA"  ~ 1500,
        montant_service == "Plus de 2000 FCFA"        ~ 2500,
        TRUE ~ NA_real_
      ),
      consent_payer = factor(
        ifelse(service_payant == "Oui", "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ montant_mensuel_fcfa, consent_payer")
}

# ============================================================================
# MODULE III — ENVIRONNEMENT COMMUNAUTAIRE : VARIABLES DÉRIVÉES
# ============================================================================
message("\n[3-III] Variables environnementales et communautaires")

# --- III.1 Score de salubrité perçue du quartier (composite) -----------------
# Basé sur : dépôts sauvages (III_12), eaux usées (III_11), nuisibles (III_17),
# qualité balayage (III_19), bacs ordures (III_3)
score_vars <- c("freq_depots_sauvages", "freq_eaux_usees_rue",
                "satisfaction_bacs", "qualite_balayage")
score_vars_present <- intersect(score_vars, names(df))

if ("freq_depots_sauvages" %in% names(df)) {
  df <- df %>%
    mutate(
      score_depot_sauvage = case_when(
        freq_depots_sauvages == "Oui, frequemment" ~ 0,
        freq_depots_sauvages == "Oui, rarement"    ~ 1,
        freq_depots_sauvages == "Non, jamais"       ~ 2,
        TRUE ~ NA_real_
      )
    )
}

if ("freq_eaux_usees_rue" %in% names(df)) {
  df <- df %>%
    mutate(
      score_eaux_usees = case_when(
        freq_eaux_usees_rue == "Oui, très souvent" ~ 0,
        freq_eaux_usees_rue == "Oui, rarement"     ~ 1,
        freq_eaux_usees_rue == "Non, jamais"        ~ 2,
        TRUE ~ NA_real_
      )
    )
}

# Score global salubrité perçue (0 = très insalubre, 6 = très salubre)
score_components <- intersect(c("score_depot_sauvage", "score_eaux_usees"), names(df))
if (length(score_components) > 0) {
  df <- df %>%
    mutate(
      score_salubrite_quartier = rowSums(
        across(all_of(score_components)), na.rm = FALSE
      ),
      salubrite_quartier_cat = cut(
        score_salubrite_quartier,
        breaks = c(-Inf, 1, 3, Inf),
        labels = c("Faible", "Moyenne", "Bonne"),
        right  = TRUE
      )
    )
  message("  ✓ score_salubrite_quartier, salubrite_quartier_cat")
}

# --- III.2 Présence de nuisibles (multi-choix → indicateurs binaires) --------
nuis_cols   <- paste0("nuis_", c("moustiques","mouches","cafards",
                                   "souris","vers","rats","autre"))
nuis_labels <- c("Moustiques","Mouches","Cafards","Souris","Vers","Rats","Autre")
df <- combine_multichoix(df,
  cols    = intersect(nuis_cols, names(df)),
  labels  = nuis_labels[nuis_cols %in% names(df)],
  new_col = "nuisibles_txt"
)
nuis_presents <- intersect(nuis_cols, names(df))
if (length(nuis_presents) > 0) {
  df <- df %>%
    mutate(
      nb_types_nuisibles = rowSums(
        across(all_of(nuis_presents)), na.rm = TRUE
      ),
      presence_nuisibles = factor(
        ifelse(nb_types_nuisibles > 0, "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ nuisibles_txt, presence_nuisibles, nb_types_nuisibles")
}

# --- III.3 Accès aux services (public vs privé) ------------------------------
if ("acces_benne_tasseuse" %in% names(df)) {
  df <- df %>%
    mutate(
      acces_service_public  = factor(
        ifelse(acces_benne_tasseuse == "Oui", "Oui", "Non"),
        levels = c("Oui", "Non")
      ),
      acces_service_prive = factor(
        ifelse(!is.na(service_alternatif) & trimws(service_alternatif) != "", "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ acces_service_public, acces_service_prive")
}

# ============================================================================
# MODULE IV — CONSÉQUENCES SANITAIRES
# ============================================================================
message("\n[3-IV] Variables sanitaires")

# --- IV.1 Maladies liées à l'insalubrité (multi-choix) ----------------------
mal_cols   <- paste0("mal_", c("fievre","asthme","rhume","sinusite","toux",
                                "nausees","demangeaisons","aucune","autre"))
mal_labels <- c("Fièvre","Asthme","Rhume","Sinusite","Toux",
                "Nausées/vomissements","Démangeaisons","Aucune","Autre")
df <- combine_multichoix(df,
  cols    = intersect(mal_cols, names(df)),
  labels  = mal_labels[mal_cols %in% names(df)],
  new_col = "maladies_declarees_txt"
)

# Maladies respiratoires (asthme + toux + sinusite + rhume)
resp_cols <- intersect(c("mal_asthme", "mal_toux", "mal_sinusite", "mal_rhume"), names(df))
if (length(resp_cols) > 0) {
  df <- df %>%
    mutate(
      maladie_respiratoire = as.integer(
        rowSums(across(all_of(resp_cols)), na.rm = TRUE) > 0
      )
    )
}

# Charge morbide totale (nb types de maladies déclarées, hors "aucune")
mal_actives <- intersect(
  setdiff(mal_cols, "mal_aucune"),
  names(df)
)
if (length(mal_actives) > 0) {
  df <- df %>%
    mutate(
      nb_maladies_declarees = rowSums(
        across(all_of(mal_actives)), na.rm = TRUE
      ),
      menage_malade = factor(
        ifelse(mal_aucune == 0 | is.na(mal_aucune), "Oui", "Non"),
        levels = c("Oui", "Non")
      )
    )
  message("  ✓ maladies_declarees_txt, maladie_respiratoire, nb_maladies_declarees, menage_malade")
}

# ============================================================================
# SAUVEGARDE DE LA TABLE CONSOLIDÉE FINALE
# ============================================================================

# Suppression des variables internes de flag (garder seulement les analytiques)
vars_flag <- grep("^flag_", names(df), value = TRUE)

# Table principale sans les colonnes _v* brutes (elles sont remplacées par les dérivées)
v_brutes <- grep("^_v[0-9]+$", names(df), value = TRUE)

df_final <- df %>% select(-any_of(v_brutes))

fwrite(df_final, file.path(OUTPUT_PATH, "03_insalubrite_analytique.csv"))
message(sprintf("\n✅ [Étape 3 terminée] → 03_insalubrite_analytique.csv (%d obs × %d var)",
                nrow(df_final), ncol(df_final)))
message("   → Prochaine étape : cleansurvey/4_qaqc/4_qaqc.R")
