# Pipeline de traitement — Insalubrité urbaine et gestion des déchets ménagers (Sénégal)

Projet de traitement de données — Enquête 2022-2023, région de Dakar (N=2474 ménages, 52 communes).

## 1. Objectif

Construire un pipeline **reproductible et scalable** qui transforme le fichier brut
`.dta` (Kobo/ODK exporté en Stata) en une table consolidée analysable, accompagnée
d'un rapport QAQC, en respectant la logique :

```
input/ (brut) → dictionnaires → nettoyage → dérivation → output/ (table finale + QAQC)
```

Le pipeline reprend l'architecture du cours (`cleansurvey`, pattern dictionnaire de
variables / dictionnaire de modalités), adaptée à un fichier mono-table (ménage)
au lieu de la structure ménage/individu du cours.

## 2. Structure du projet

```
projet_insalubrite/
├── README.md                          ← ce fichier
├── Requirements.R                      ← installation des packages (1 fois)
├── run_all.R                           ← lance tout le pipeline
│
├── input/
│   └── 22_23_Insalubrite.dta           ← fichier brut (2474 obs × 139 var)
│
├── dictionaries/
│   ├── dictionary_insalubrite_init.csv     ← dictionnaire auto-généré (référence)
│   ├── dictionary_insalubrite_filled.xlsx  ← dictionnaire COMPLÉTÉ (utilisé par le pipeline)
│   ├── dictionary_modality_init.csv        ← modalités à recoder (généré étape 1)
│   ├── commune_milieu_init.csv             ← référence brute communes
│   ├── commune_milieu_filled.csv           ← classification urbain/périurbain (À VALIDER)
│   └── data_quality_issues.csv             ← documentation des anomalies du fichier source
│
├── cleansurvey/
│   ├── config.R                        ← chemins & paramètres (SEUL fichier à modifier
│   │                                       pour une nouvelle édition de l'enquête)
│   ├── utils.R                         ← fonctions génériques réutilisables
│   ├── 0_setup/0_get_dict.R            ← génère le dictionnaire brut (1 fois / édition)
│   ├── 1_dictionary/1_apply_dict.R     ← applique le dictionnaire (renommage/typage)
│   ├── 2_clean/2_clean.R               ← aberrants, cohérence, NA, imputation
│   ├── 3_derive/3_derive.R             ← construction des variables analytiques
│   └── 4_qaqc/4_qaqc.R                 ← rapport QAQC (xlsx, 9 feuilles)
│
└── output/                             ← généré par le pipeline (voir §5)
```

## 3. Installation et exécution

```r
# 1. Ouvrir le projet dans RStudio (working directory = racine du projet)
setwd("chemin/vers/projet_insalubrite")

# 2. Installer les packages (une seule fois)
source("Requirements.R")

# 3. Lancer le pipeline complet
source("run_all.R")
```

Durée d'exécution attendue : < 1 minute (2474 lignes).

## 4. Pour une nouvelle édition de l'enquête (reproductibilité)

1. Déposer le nouveau fichier `.dta` dans `input/`
2. Modifier uniquement `RAW_FILE_NAME` dans `cleansurvey/config.R`
3. Décommenter l'étape 0 dans `run_all.R` et l'exécuter pour régénérer
   `dictionary_insalubrite_init.csv`
4. Comparer avec `dictionary_insalubrite_filled.xlsx` existant : si les noms de
   variables Kobo sont identiques (même structure de questionnaire), le
   dictionnaire rempli reste valable tel quel.
5. Si de nouvelles variables apparaissent, compléter uniquement les nouvelles
   lignes dans `dictionary_insalubrite_filled.xlsx` (module, var_new, label_new,
   type_new, keep)
6. Relancer `run_all.R`

Aucune autre modification de code n'est nécessaire — c'est tout l'intérêt du
pattern dictionnaire.

## 5. Fichiers produits dans output/

| Fichier | Description |
|---|---|
| `01_insalubrite_labeled.csv` | Après renommage et typage (dictionnaire appliqué) |
| `02_insalubrite_clean.csv` | Après traitement aberrants/cohérence/imputation |
| `02_flags_coherence.csv` | Rapport des incohérences détectées (règles métier) |
| `02_taux_completion.csv` | Taux de remplissage par variable |
| `03_insalubrite_analytique.csv` | **TABLE FINALE CONSOLIDÉE** (livrable principal) |
| `04_QAQC_insalubrite.xlsx` | Rapport qualité complet (9 feuilles, voir §6) |

## 6. Contenu du rapport QAQC (04_QAQC_insalubrite.xlsx)

1. **Metadonnees** — identification du fichier, limites connues
2. **Limites_Donnees** — anomalies du fichier source et stratégie retenue (cf. §7)
3. **Completion** — taux de NA par variable, avec code couleur
4. **Incoherences** — résultat des contrôles de cohérence métier
5. **Stats_Menage_CM** — statistiques descriptives module I
6. **Stats_Dechets** — statistiques descriptives module II
7. **Stats_Environnement** — statistiques descriptives module III
8. **Stats_Sante** — statistiques descriptives module IV
9. **Analyse_NA** — patterns de données manquantes (base pour test MCAR/MAR)

## 7. Limites connues de la base de données — IMPORTANT

Ces limites sont documentées intégralement dans `dictionaries/data_quality_issues.csv`
et reprises dans le rapport QAQC (feuille 1bis).

### 7.1 Variables demandées dans l'énoncé mais absentes de cette édition

La base Insalubrité 2022-2023 ne collecte pas :
- Dépenses du ménage
- Actifs du ménage (biens d'équipement)
- Statut d'emploi du CM
- Secteur d'emploi du CM
- Revenu du CM

Ces colonnes sont créées dans la table finale avec valeur `NA`, à des fins de
compatibilité de schéma avec d'éventuelles autres éditions, et signalées
explicitement dans le rapport QAQC.

### 7.2 Variables avec codes Kobo non labellisés

9 variables (`type_logement`, `type_conteneur_stockage`, `lieu_stockage`,
`service_alternatif`, `raison_preference_service`, `raison_insatisf_bacs`,
`gestionnaire_ordures_place`, `gestionnaire_ordures_marche`, `auteur_campagne`)
sont exportées avec des codes numériques bruts (1, 2, 3... "other") **sans
dictionnaire de labels Stata associé** dans le fichier source. Une tentative de
reconstruction des libellés à partir du contexte (réponses "autre" associées,
distribution des fréquences) n'a pas permis d'aboutir à un mapping fiable.

**Décision retenue** : ces variables sont conservées telles quelles (codes bruts)
dans la table analytique, avec documentation explicite. Elles restent exploitables
pour des analyses de fréquence/association, mais nécessitent le questionnaire
Kobo original pour interprétation littérale des modalités.

### 7.3 Variable avec codes résiduels non documentés

`acces_benne_tasseuse` (II_13) présente, en plus des codes `{1=Oui, 2=Non}`
documentés, des codes résiduels `{3, 4, 5, 6}` (28 observations, ~1.1%) non
couverts par le dictionnaire Stata. Ces valeurs sont traitées comme manquantes
(NA) après documentation, plutôt que supposées arbitrairement.

### 7.4 Milieu de résidence (urbain/périurbain)

La variable `milieu_residence` est construite par jointure avec
`dictionaries/commune_milieu_filled.csv`, qui contient une **classification
indicative** des 52 communes (urbain dense / urbain Pikine-Guédiawaye /
périurbain) basée sur leur statut administratif dans la région de Dakar.

**⚠️ Cette classification doit être validée ou corrigée avant utilisation finale**
— elle constitue une proposition de départ, pas une source officielle vérifiée.

## 8. Méthodologie de traitement des données manquantes

Conforme à la logique vue en cours (Cours 5 — Techniques avancées d'imputation) :

1. **Diagnostic** : taux de NA par variable (`02_taux_completion.csv`), patterns
   de cooccurrence des NA (`feuille 8_Analyse_NA` du QAQC)
2. **Traitement des aberrants en amont** : les valeurs hors bornes plausibles
   (âge, taille du ménage...) sont mises à NA avant imputation, pour éviter de
   biaiser les statistiques d'imputation
3. **Imputation** :
   - Variables numériques clés : médiane (`*_imputed`, variable originale conservée)
   - Variables catégorielles à faible taux de NA (<20%) : mode
   - Variables avec NA élevé (>20%) : non imputées, signalées dans le QAQC,
     laissées à l'appréciation de l'analyste (MICE recommandé si besoin, package
     déjà chargé dans `Requirements.R`)
4. Toute valeur imputée est traçable (variable `_imputed` séparée de l'original)

## 9. Contrôles de cohérence implémentés

| Règle | Description |
|---|---|
| `flag_tri_revente` | Revente déclarée sans tri préalable (incohérent) |
| `flag_satisf_sans_acces` | Satisfaction collecte évaluée sans accès au service |
| `flag_montant_gratuit` | Montant payé renseigné malgré service déclaré gratuit |
| `flag_age_cm_mineur` | Chef de ménage déclaré mineur (<18 ans) |
| `flag_taille_neg` | Taille du ménage nulle ou négative |

D'autres règles peuvent être ajoutées dans `cleansurvey/2_clean/2_clean.R`
(section C) en suivant le même pattern (`add_coherence_flag()`).

## 10. Variables dérivées construites (cœur analytique du projet)

| Variable | Construction |
|---|---|
| `milieu_residence` | Jointure avec classification commune → urbain/périurbain |
| `alphabetise_cm` | OU logique sur 5 langues d'alphabétisation (I_12_1 à I_12_5) |
| `taille_menage`, `nb_adultes`, `nb_enfants_total`, `ratio_dep` | Combinaison des 4 compteurs démographiques |
| `sources_dechets_txt`, `nature_dechets_txt`, `nuisibles_txt`, `maladies_declarees_txt` | Agrégation des colonnes binaires multi-choix Kobo en texte lisible |
| `presence_dechets_dangereux` | Médicaments OU électroménager présents dans les déchets |
| `score_autonomie_traitement`, `traite_en_autonomie` | Score sur 4 pratiques (enfouissement/incinération/recyclage/compostage) |
| `mode_evacuation_principal` | Hiérarchie : benne publique > service privé > autonomie > dépôt non contrôlé |
| `montant_mensuel_fcfa` | Recodage des tranches de montant en point médian numérique (0 FCFA si gratuit) |
| `consent_payer` | Le service est-il payant (Oui/Non) |
| `score_salubrite_quartier`, `salubrite_quartier_cat` | Score composite (dépôts sauvages + eaux usées) |
| `presence_nuisibles`, `nb_types_nuisibles` | Indicateurs sur 7 types de nuisibles |
| `acces_service_public`, `acces_service_prive` | Distinction public (benne) vs privé/alternatif |
| `maladie_respiratoire`, `nb_maladies_declarees`, `menage_malade` | Indicateurs composites santé liée à l'insalubrité |

## 11. Auteurs

Groupe 3 & 5 — Projet de traitement de données, ENSAE.
