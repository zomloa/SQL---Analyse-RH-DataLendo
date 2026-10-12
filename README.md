# Projet RH Analytics – DataLendo

Analyse SQL des effectifs, du turnover et de la performance des employés de DataLendo, en réponse aux 15 questions du manager RH.

- **Moteur** : SQLite 3.35+ (fonctions fenêtre, `julianday`, `strftime`). Les requêtes sont en SQL standard, sauf les fonctions de date, à adapter pour PostgreSQL / SQL Server (voir [Portabilité](#portabilité)).
- **Date de référence** : **2026-10-10** (« aujourd'hui »), modifiable avec `--ref-date`.
- **Résultat clé** : 1 329 employés actifs, 23 départs sur 12 mois, turnover cumulé de 11,4 %. Les écarts entre départements ne sont pas statistiquement significatifs. Détails dans [Insights_RH_DataLendo.docx](Insights_RH_DataLendo.docx).

## Contenu du dépôt

```
├── employes.csv, departements.csv, performances.csv, turnover.csv   données sources (non modifiées)
├── sql/
│   ├── 00_schema.sql          tables, clés, index, table de paramètres (date de référence)
│   ├── 01_enrichissement.sql  colonnes dérivées -> evaluations, perf_employe, employes_enrichi
│   └── 02_analyses.sql        les 15 questions (19 requêtes, une par bloc « -- @Qxx »)
├── run_analysis.py            charge les CSV, exécute les 3 scripts SQL, exporte les résultats
├── scripts/make_figures.py    génère les graphiques du document d'insights
├── outputs/
│   ├── dataset_enrichi.csv    LIVRABLE : 1 500 employés x 28 colonnes
│   ├── Q01.csv … Q15.csv      résultat de chaque requête
│   ├── resultats_analyses.xlsx  tout dans un classeur (une feuille par requête + dataset enrichi)
│   ├── rh_datalendo.db        base SQLite prête à interroger
│   └── figures/               graphiques PNG
├── Insights_RH_DataLendo.docx LIVRABLE : synthèse et recommandations RH
└── README.md                  ce fichier
```

## Reproduire

```bash
pip install pandas openpyxl          # openpyxl : export Excel ; matplotlib pour les graphiques
python run_analysis.py               # date de référence par défaut : 2026-10-10
python run_analysis.py --ref-date 2025-12-31   # autre date de référence
python scripts/make_figures.py .     # (optionnel) régénère les graphiques
```

Les CSV sont chargés dans SQLite, les scripts de `sql/` sont exécutés dans l'ordre, et chaque requête de `02_analyses.sql` est exportée dans `outputs/`. On peut aussi ouvrir `outputs/rh_datalendo.db` avec n'importe quel client SQLite et rejouer les requêtes.

## Les tables sources

| Table | Lignes | Clé | Colonnes |
|---|---|---|---|
| `departements` | 10 | `id_departement` | `nom_departement`, `manager`, `budget` |
| `employes` | 1 500 | `id_employe` | `nom`, `prenom`, `poste`, `departement_id`, `date_embauche` (2019-01-01 → 2023-12-30), `date_depart` (vide pour 1 300 employés), `salaire` |
| `performances` | 18 000 | `id_performance` | `id_employe`, `date_evaluation` (12 trimestres, 2022-01-01 → 2024-10-01), `score` (50–99), `objectifs_atteints` (True/False) |
| `turnover` | 200 | `id_depart` | `id_employe`, `date_depart`, `type_depart` (volontaire / involontaire), `anciennete` |

Relations : `employes.departement_id → departements`, `performances.id_employe → employes`, `turnover.id_employe → employes` (1 ligne turnover = 1 employé parti, aucun doublon). Les 12 évaluations sont présentes pour chaque employé, sans valeur manquante.

## Transformations et dataset enrichi

`sql/01_enrichissement.sql` produit trois tables :

1. **`evaluations`** : `performances` + `trimestre` (ex. `2024-T3`), `annee` et `eval_valide` (voir hypothèse H4).
2. **`perf_employe`** : par employé, sur évaluations valides : `nb_evals_valides`, `score_moyen`, `score_min/max`, `taux_objectifs_pct`, `derniere_evaluation`, `categorie_performance`.
3. **`employes_enrichi`** : une ligne par employé (exporté dans `outputs/dataset_enrichi.csv`).

Colonnes dérivées du dataset enrichi :

| Colonne | Définition |
|---|---|
| `statut`, `est_parti` | `parti` si `date_depart` ≤ date de référence, sinon `actif` |
| `depart_planifie` | 1 si `date_depart` est postérieure à la date de référence (actif, mais départ prévu) |
| `type_depart` | volontaire / involontaire (table `turnover`) |
| `annee_depart` | année du départ, si le départ est réalisé |
| `anciennete_ans` | (date de départ, ou date de référence si actif) − `date_embauche`, en années de 365,25 jours |
| `tranche_anciennete` | `< 1 an`, `1 à < 3 ans`, `3 à < 5 ans`, `5 à < 7 ans`, `7 ans et +` |
| `cohorte_embauche` | année d'embauche (2019 à 2023) |
| `retenu_12m`, `retenu_24m` | 1 si l'employé est resté au moins 12 / 24 mois ; NULL si la période n'est pas encore observable |
| `nb_evals_valides`, `score_moyen`, `taux_objectifs_pct`, `derniere_evaluation` | issus de `perf_employe` |
| `categorie_performance` | `faible` (< 70), `moyen` (70 à < 78), `élevé` (≥ 78), ou `non évalué (<4 évals)` |
| `nb_evals_hors_periode` | nombre d'évaluations de l'employé exclues car hors période d'emploi |
| `date_depart_turnover`, `flag_date_turnover_incoherente` | date de la table `turnover` et indicateur d'écart avec `employes` |

## Hypothèses et choix méthodologiques

| # | Hypothèse | Pourquoi |
|---|---|---|
| **H1** | La date de référence est **2026-10-10**. | Les questions parlent de « actuellement » et de « 12 derniers mois » ; la date du jour est utilisée. Un seul paramètre (`params.ref_date`) pilote tout. |
| **H2** | Un employé est **parti** si `date_depart` ≤ date de référence. Une `date_depart` postérieure est un **départ planifié** : l'employé est actif. | 29 départs sont datés entre octobre 2026 et 2029. Sans cette règle, on compterait comme partis des gens qui ne le sont pas encore. Si on les compte comme partis, les actifs passent de 1 329 à 1 300. |
| **H3** | `employes.date_depart` est la source de vérité pour les dates et l'ancienneté. De `turnover`, seul `type_depart` est utilisé. | `turnover.date_depart` et `turnover.anciennete` sont incohérentes (voir ci-dessous). |
| **H4** | Une évaluation est **valide** si `date_embauche` ≤ `date_evaluation` ≤ `date_depart` (si renseignée). Seules les évaluations valides entrent dans les calculs de performance. | 3 430 évaluations (19 %) sont hors période d'emploi. |
| **H5** | La **catégorie de performance** repose sur le score moyen individuel (évaluations valides, minimum 4) : faible < 70, moyen 70 à < 78, élevé ≥ 78. | Les scores individuels sont très concentrés (moyenne 74,5 ; écart-type 5). Ces seuils correspondent à environ P20 et P75 : 17 % / 59 % / 24 %. Des seuils fixes à 65 et 80 auraient donné 3 % de profils faibles. À ajuster selon la politique RH. |
| **H6** | Le **feedback** est approximé par les évaluations de performance. | Aucune table de feedback n'existe. |
| **H7** | Le **taux de turnover** d'un département = départs réalisés / nombre d'employés embauchés dans ce département depuis 2019. | Pas d'historique d'effectif mensuel : pas de dénominateur annuel moyen possible. |
| **H8** | Les **3 derniers trimestres** = les 3 dernières dates d'évaluation du jeu de données (2024-04-01, 2024-07-01, 2024-10-01). | Les évaluations s'arrêtent en octobre 2024 ; il n'y en a pas dans les 3 trimestres précédant la date de référence. |
| **H9** | Les questions sur des personnes (Q5, Q7, Q8, Q12) portent sur les **employés actifs**. Les questions sur des tendances (Q3, Q9, Q10, Q11, Q14, Q15) portent sur **tous les employés**. | Q5, Q7, Q8 : une liste d'actions RH n'a de sens que pour des personnes encore là. |

### Problèmes de qualité de données constatés

| Constat | Mesure | Traitement |
|---|---|---|
| Dates de départ de `turnover` différentes de celles de `employes` | 200 sur 200 ; écart de −8,8 à +8,3 ans ; 32 antérieures à l'embauche. Les deux colonnes contiennent les mêmes dates, mais attribuées à des employés différents. | H3 : `employes` fait foi. |
| `turnover.anciennete` ≠ ancienneté recalculée | écart moyen 2,9 ans | Non utilisée ; ancienneté recalculée. |
| Départs datés dans le futur | 29 départs (octobre 2026 → 2029) | H2 : départs planifiés. |
| Évaluations avant l'embauche / après le départ | 2 621 + 809 = 3 430 sur 18 000 | H4 : exclues. |
| `objectifs_atteints` sans lien avec `score` | score moyen 74,48 (non atteints) vs 74,47 (atteints) | Les deux indicateurs sont rapportés ; `taux_objectifs_pct` doit être lu avec prudence. |
| `poste` indépendant du département | 5 postes répartis uniformément dans les 10 départements ; salaire uniforme entre 802 et 4 999 quel que soit le poste | Signalé ; aucune analyse n'en dépend. |
| Aucune embauche après décembre 2023, aucune évaluation après octobre 2024 | – | Limite signalée dans le document d'insights. |
| Données anonymisées (`Nom_1`, `Prenom_1`) | – | Les employés sont identifiés par `id_employe`. |

L'encodage des CSV est UTF-8 valide (les accents de `Opérations` et `Direction Générale` sont corrects).

## Méthodologie par question

| Q | Question | Requête | Définition retenue | Résultat (date de réf. 2026-10-10) |
|---|---|---|---|---|
| 1 | Employés actifs | `Q01` | `statut = 'actif'` (H2) | **1 329** (dont 29 avec départ planifié) |
| 2 | Départs sur 12 mois | `Q02` | départs réalisés avec `date_depart` dans ]ref − 12 mois ; ref] | **23** (8 volontaires, 15 involontaires) |
| 3 | Turnover le plus élevé | `Q03` | H7 ; classement par taux | **Opérations 14,7 %**, Direction Générale 13,8 %, Juridique 12,4 % ; mini RH 9,2 % |
| 4 | Salaire moyen par département | `Q04` | moyenne sur les actifs (colonne annexe : tous employés) | de **2 704** (Marketing) à **3 107** (Finance) |
| 5 | Plus de 5 ans d'ancienneté | `Q05` | actifs embauchés avant ref − 5 ans (liste complète) | **718** employés |
| 6 | Classement des départements par performance trimestrielle | `Q06a`, `Q06b` | score moyen par trimestre et département (évaluations valides), rang par trimestre ; puis classement global | Opérations 74,87 > Finance 74,83 > Service Client 74,80 … Marketing 73,77 |
| 7 | Top 10 sur 3 trimestres | `Q07` | actifs avec 3 évaluations valides ; tri par score moyen, puis objectifs atteints, puis id | n° **1156** (97,33), 1009 (96,00), 536 (95,00) … |
| 8 | Moins performants | `Q08a`, `Q08b` | actifs de catégorie `faible` ; répartition par département | **228** employés ; Ventes 20,8 % des évalués, Opérations 10,9 % |
| 9 | Rétention par cohorte | `Q09` | % toujours actifs, + rétention à 12 et 24 mois | 2019 : 87,5 % · 2020 : 85,4 % · 2021 : 88,8 % · 2022 : 88,0 % · 2023 : 93,3 % ; global 88,6 % |
| 10 | Départements qui recrutent le plus | `Q10` | nombre d'embauches, total et par année | RH 164, Juridique 161, Informatique et Ventes 159 |
| 11 | Volontaire vs involontaire | `Q11` | départs réalisés et départs enregistrés | **49,7 % / 50,3 %** (réalisés) ; 49,5 % / 50,5 % (tous) |
| 12 | Postes par ancienneté | `Q12` | croisement poste × tranche d'ancienneté, actifs | Répartition homogène ; ancienneté moyenne 5,1 à 5,3 ans selon le poste |
| 13 | Employés sans feedback cette année | `Q13a`, `Q13b` | actifs sans évaluation dans l'année de référence (H6) | **1 329 sur 1 329** (dernière évaluation : 2024-10-01). En 2024 : 0 actif sans évaluation |
| 14 | Segmentation faible / moyen / élevé | `Q14a`, `Q14b` | H5 | 251 faible · 852 moyen · 345 élevé · 52 non évalués |
| 15 | Tableau de synthèse | `Q15` | KPIs par département × cohorte, par département, par cohorte et global (66 lignes) | – |

Les résultats complets sont dans `outputs/Qxx.csv` et `outputs/resultats_analyses.xlsx`.

## Vérification

Les chiffres clés (Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8, Q9, Q11, Q14) ont été recalculés indépendamment avec pandas, sans passer par le SQL : les résultats concordent. Cette vérification a permis de corriger un bug dans la première version de Q5 : le filtre portait sur l'ancienneté arrondie à 2 décimales et excluait 3 employés (715 au lieu de 718). Le filtre utilise désormais la date d'embauche.

**Tests statistiques** (tests de permutation, 5 000 tirages, sur les départements) :

| Question testée | Écart observé | p-valeur | Conclusion |
|---|---|---|---|
| Les scores moyens diffèrent-ils entre départements ? | 1,10 point entre le meilleur et le moins bon (74,87 contre 73,77, moyenne des scores trimestriels de Q6b) | 0,63 | Pas de différence significative |
| Les taux de turnover diffèrent-ils entre départements ? | 5,5 points | 0,89 | Pas de différence significative |

Autres corrélations calculées : salaire ↔ score moyen : −0,01 ; salaire ↔ ancienneté : +0,01.

## Limites

- Les classements par département (turnover, performance, part de profils faibles) sont indicatifs : les écarts sont compatibles avec le hasard.
- Le turnover est cumulé depuis 2019, pas annualisé (pas d'effectif mensuel).
- Les seuils de performance (70 / 78) sont un choix méthodologique, pas une règle RH de l'entreprise.
- La rétention actuelle des cohortes récentes est mécaniquement plus haute (moins de temps pour partir) ; la comparer à ancienneté égale (12 et 24 mois).
- `budget` (table `departements`) n'est pas exploité : sa définition (annuel ? masse salariale ?) n'est pas précisée.

## Portabilité

Les scripts utilisent SQLite. Pour PostgreSQL ou SQL Server :

| SQLite | PostgreSQL | SQL Server |
|---|---|---|
| `julianday(a) - julianday(b)` | `a::date - b::date` | `DATEDIFF(day, b, a)` |
| `strftime('%Y', d)` | `EXTRACT(YEAR FROM d)` | `YEAR(d)` |
| `date(d, '-12 months')` | `d - INTERVAL '12 months'` | `DATEADD(month, -12, d)` |
| `SUM(condition)` | `SUM((condition)::int)` | `SUM(CASE WHEN condition THEN 1 ELSE 0 END)` |
| `CREATE TABLE ... AS` | identique | `SELECT ... INTO` |
