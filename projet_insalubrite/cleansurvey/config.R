# =============================================================================
# config.R — Configuration globale du pipeline Insalubrité
# Projet   : Gestion des déchets solides et insalubrité urbaine au Sénégal
# Données  : Enquête 22_23_Insalubrite.dta (N=2474, 139 variables)
# =============================================================================
# Ce fichier est le SEUL à modifier si les chemins changent d'une édition à l'autre.

# --- Chemins -----------------------------------------------------------------
MAIN_DATA_PATH  <- "input"           # dossier des fichiers bruts
AUX_FILE_PATH   <- "dictionaries"    # dictionnaires (var, modalités, communes)
OUTPUT_PATH     <- "output"          # sorties finales

# --- Nom du fichier source ---------------------------------------------------
# Pour une nouvelle édition, ne changer que cette ligne
RAW_FILE_NAME   <- "22_23_Insalubrite.dta"

# --- Paramètres de nettoyage -------------------------------------------------
# Seuil d'âge CM : valeurs en dehors → aberrantes → NA
AGE_CM_MIN      <- 15
AGE_CM_MAX      <- 100

# Seuil d'âge répondant
AGE_REP_MIN     <- 18
AGE_REP_MAX     <- 100

# Seuil taille ménage (nb membres total)
TAILLE_MEN_MAX  <- 30

# Taux de NA au-delà duquel une variable est flaggée dans le QAQC
SEUIL_NA_FLAG   <- 0.20   # 20 %

# --- Modules du questionnaire ------------------------------------------------
# Préfixes des variables par module (pour documentation et boucles)
MODULE_PREFIXES <- list(
  module_I   = c("I_"),
  module_II  = c("II_"),
  module_III = c("III_"),
  module_IV  = c("IV_", "_v30", "_v31", "_v32", "_v33",
                 "_v34", "_v35", "_v36", "_v37", "_v38")
)

# --- Limites des données (variables absentes à documenter) -------------------
VARIABLES_ABSENTES <- c(
  "depenses_menage"   = "Non collecté dans cette édition",
  "actifs_menage"     = "Non collecté dans cette édition",
  "statut_emploi_cm"  = "Non collecté dans cette édition",
  "secteur_emploi_cm" = "Non collecté dans cette édition",
  "revenu_cm"         = "Non collecté dans cette édition"
)
