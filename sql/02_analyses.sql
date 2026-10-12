-- =====================================================================
-- 02_analyses.sql  |  Les 15 questions du manager
-- Dépend de : 01_enrichissement.sql (tables employes_enrichi, evaluations,
-- perf_employe) et de params.ref_date.
-- Chaque bloc "-- @Qxx" contient UNE requête ; run_analysis.py exporte le
-- résultat de chaque bloc dans outputs/.
-- =====================================================================


-- @Q01 | Combien d'employés sont actuellement actifs ?
-- Actif = pas de départ enregistré, ou départ planifié après la date de référence.
SELECT
    COUNT(*)                                                    AS employes_actifs,
    SUM(depart_planifie)                                        AS dont_depart_planifie_apres_ref,
    COUNT(*) - SUM(depart_planifie)                             AS dont_sans_aucune_date_depart,
    (SELECT COUNT(*) FROM employes_enrichi WHERE est_parti = 1) AS employes_partis,
    (SELECT ref_date FROM params)                               AS date_reference
FROM employes_enrichi
WHERE statut = 'actif';


-- @Q02 | Combien de départs sur les 12 derniers mois ?
SELECT
    COUNT(*)                                         AS departs_12_derniers_mois,
    SUM(type_depart = 'volontaire')                  AS dont_volontaires,
    SUM(type_depart = 'involontaire')                AS dont_involontaires,
    date(r.ref_date, '-12 months')                   AS periode_debut_exclu,
    r.ref_date                                       AS periode_fin
FROM employes_enrichi e
CROSS JOIN params r
WHERE e.est_parti = 1
  AND e.date_depart >  date(r.ref_date, '-12 months')
  AND e.date_depart <= r.ref_date;


-- @Q03 | Quels départements ont le turnover le plus élevé ?
-- Taux de turnover = départs réalisés / nb d'employés ayant été embauchés dans le département.
SELECT
    RANK() OVER (ORDER BY 1.0 * SUM(est_parti) / COUNT(*) DESC)  AS rang,
    nom_departement,
    COUNT(*)                                                     AS effectif_total_historique,
    SUM(est_parti)                                               AS departs_realises,
    ROUND(100.0 * SUM(est_parti) / COUNT(*), 2)                  AS taux_turnover_pct,
    SUM(CASE WHEN est_parti = 1
              AND date_depart > date((SELECT ref_date FROM params), '-12 months')
             THEN 1 ELSE 0 END)                                  AS departs_12_derniers_mois,
    COUNT(*) - SUM(est_parti)                                    AS effectif_actif
FROM employes_enrichi
GROUP BY nom_departement
ORDER BY taux_turnover_pct DESC;


-- @Q04 | Quel est le salaire moyen par département ?
SELECT
    nom_departement,
    COUNT(*)                                           AS nb_actifs,
    ROUND(AVG(salaire), 0)                             AS salaire_moyen_actifs,
    MIN(salaire)                                       AS salaire_min,
    MAX(salaire)                                       AS salaire_max,
    (SELECT ROUND(AVG(e2.salaire), 0) FROM employes_enrichi e2
      WHERE e2.nom_departement = e.nom_departement)    AS salaire_moyen_tous_employes
FROM employes_enrichi e
WHERE statut = 'actif'
GROUP BY nom_departement
ORDER BY salaire_moyen_actifs DESC;


-- @Q05 | Quels employés ont plus de 5 ans d'ancienneté ?
-- Population : employés actifs. Filtre sur la date (embauchés avant ref_date - 5 ans)
-- plutôt que sur anciennete_ans, qui est arrondie à 2 décimales.
SELECT
    id_employe, nom, prenom, poste, nom_departement,
    date_embauche, anciennete_ans, salaire
FROM employes_enrichi
WHERE statut = 'actif'
  AND date_embauche < date((SELECT ref_date FROM params), '-5 years')
ORDER BY anciennete_ans DESC, id_employe;


-- @Q06a | Classement des départements par performance moyenne trimestrielle (détail par trimestre)
-- Évaluations valides uniquement ; rang 1 = meilleure performance du trimestre.
SELECT
    ev.trimestre,
    e.nom_departement,
    COUNT(*)                                                         AS nb_evaluations,
    ROUND(AVG(ev.score), 2)                                          AS score_moyen,
    RANK() OVER (PARTITION BY ev.trimestre ORDER BY AVG(ev.score) DESC) AS rang_trimestre
FROM evaluations ev
JOIN employes_enrichi e ON e.id_employe = ev.id_employe
WHERE ev.eval_valide = 1
GROUP BY ev.trimestre, e.nom_departement
ORDER BY ev.trimestre, rang_trimestre;


-- @Q06b | Classement global des départements (moyenne des 12 trimestres)
WITH par_trimestre AS (
    SELECT ev.trimestre, e.nom_departement,
           AVG(ev.score) AS score_trim,
           RANK() OVER (PARTITION BY ev.trimestre ORDER BY AVG(ev.score) DESC) AS rang_trim
    FROM evaluations ev
    JOIN employes_enrichi e ON e.id_employe = ev.id_employe
    WHERE ev.eval_valide = 1
    GROUP BY ev.trimestre, e.nom_departement
)
SELECT
    RANK() OVER (ORDER BY AVG(score_trim) DESC)   AS rang_global,
    nom_departement,
    ROUND(AVG(score_trim), 2)                     AS score_moyen_trimestriel,
    ROUND(AVG(rang_trim), 2)                      AS rang_moyen_par_trimestre,
    MIN(rang_trim)                                AS meilleur_rang,
    MAX(rang_trim)                                AS pire_rang,
    ROUND(MAX(score_trim) - MIN(score_trim), 2)   AS amplitude_scores
FROM par_trimestre
GROUP BY nom_departement
ORDER BY rang_global;


-- @Q07 | Top 10 des employés sur les 3 derniers trimestres d'évaluation
-- 3 derniers trimestres = les 3 dernières dates d'évaluation du jeu de données.
-- Employés actifs ayant 3 évaluations valides ; départage : objectifs atteints puis id.
WITH derniers AS (
    SELECT DISTINCT date_evaluation FROM evaluations
    ORDER BY date_evaluation DESC LIMIT 3
),
agg AS (
    SELECT ev.id_employe,
           COUNT(*)                         AS nb_evals,
           ROUND(AVG(ev.score), 2)          AS score_moyen_3t,
           SUM(ev.objectifs_atteints)       AS objectifs_atteints_sur_3
    FROM evaluations ev
    WHERE ev.eval_valide = 1
      AND ev.date_evaluation IN (SELECT date_evaluation FROM derniers)
    GROUP BY ev.id_employe
    HAVING COUNT(*) = 3
)
SELECT
    ROW_NUMBER() OVER (ORDER BY a.score_moyen_3t DESC, a.objectifs_atteints_sur_3 DESC, a.id_employe) AS rang,
    a.id_employe, e.nom, e.prenom, e.poste, e.nom_departement,
    a.score_moyen_3t, a.objectifs_atteints_sur_3
FROM agg a
JOIN employes_enrichi e ON e.id_employe = a.id_employe
WHERE e.statut = 'actif'
ORDER BY rang
LIMIT 10;


-- @Q08a | Employés les moins performants et leur département (catégorie 'faible', actifs)
SELECT
    id_employe, nom, prenom, poste, nom_departement,
    nb_evals_valides, score_moyen, taux_objectifs_pct, categorie_performance
FROM employes_enrichi
WHERE statut = 'actif'
  AND categorie_performance = 'faible'
ORDER BY score_moyen ASC, id_employe;


-- @Q08b | Répartition des employés à performance faible par département (actifs)
SELECT
    nom_departement,
    SUM(categorie_performance = 'faible')                                   AS nb_faible,
    SUM(categorie_performance <> 'non évalué (<4 évals)')                   AS nb_evalues,
    ROUND(100.0 * SUM(categorie_performance = 'faible')
          / SUM(categorie_performance <> 'non évalué (<4 évals)'), 1)       AS pct_faible
FROM employes_enrichi
WHERE statut = 'actif'
GROUP BY nom_departement
ORDER BY pct_faible DESC;


-- @Q09 | Rétention moyenne par cohorte d'embauche (année d'embauche)
SELECT
    cohorte_embauche,
    COUNT(*)                                              AS embauches,
    SUM(1 - est_parti)                                    AS toujours_actifs,
    ROUND(100.0 * SUM(1 - est_parti) / COUNT(*), 1)       AS retention_actuelle_pct,
    ROUND(100.0 * SUM(retenu_12m) / COUNT(retenu_12m), 1) AS retention_12_mois_pct,
    ROUND(100.0 * SUM(retenu_24m) / COUNT(retenu_24m), 1) AS retention_24_mois_pct,
    ROUND(AVG(anciennete_ans), 2)                         AS anciennete_moyenne_ans
FROM employes_enrichi
GROUP BY cohorte_embauche
UNION ALL
SELECT
    'Toutes cohortes',
    COUNT(*),
    SUM(1 - est_parti),
    ROUND(100.0 * SUM(1 - est_parti) / COUNT(*), 1),
    ROUND(100.0 * SUM(retenu_12m) / COUNT(retenu_12m), 1),
    ROUND(100.0 * SUM(retenu_24m) / COUNT(retenu_24m), 1),
    ROUND(AVG(anciennete_ans), 2)
FROM employes_enrichi
ORDER BY 1;


-- @Q10 | Quels départements recrutent le plus souvent ?
SELECT
    RANK() OVER (ORDER BY COUNT(*) DESC)                         AS rang,
    nom_departement,
    COUNT(*)                                                     AS embauches_total,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS part_des_embauches_pct,
    SUM(cohorte_embauche = '2019')                               AS e2019,
    SUM(cohorte_embauche = '2020')                               AS e2020,
    SUM(cohorte_embauche = '2021')                               AS e2021,
    SUM(cohorte_embauche = '2022')                               AS e2022,
    SUM(cohorte_embauche = '2023')                               AS e2023,
    ROUND(COUNT(*) / 5.0, 1)                                     AS embauches_moyennes_par_an
FROM employes_enrichi
GROUP BY nom_departement
ORDER BY embauches_total DESC;


-- @Q11 | Proportion de départs volontaires vs involontaires
-- Deux lectures : les départs réalisés (<= date de référence) et tous les départs enregistrés.
SELECT
    type_depart,
    SUM(est_parti)                                            AS departs_realises,
    ROUND(100.0 * SUM(est_parti) / SUM(SUM(est_parti)) OVER (), 1)  AS pct_departs_realises,
    COUNT(*)                                                  AS departs_enregistres_total,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_departs_enregistres
FROM employes_enrichi
WHERE type_depart IS NOT NULL
GROUP BY type_depart
ORDER BY type_depart DESC;


-- @Q12 | Distribution des postes par ancienneté (employés actifs)
SELECT
    poste,
    SUM(tranche_anciennete = '< 1 an')       AS "< 1 an",
    SUM(tranche_anciennete = '1 à < 3 ans')  AS "1 à < 3 ans",
    SUM(tranche_anciennete = '3 à < 5 ans')  AS "3 à < 5 ans",
    SUM(tranche_anciennete = '5 à < 7 ans')  AS "5 à < 7 ans",
    SUM(tranche_anciennete = '7 ans et +')   AS "7 ans et +",
    COUNT(*)                                 AS total_actifs,
    ROUND(AVG(anciennete_ans), 2)            AS anciennete_moyenne_ans
FROM employes_enrichi
WHERE statut = 'actif'
GROUP BY poste
ORDER BY total_actifs DESC;


-- @Q13a | Employés actifs sans feedback (= évaluation) dans l'année de référence
-- Il n'existe pas de table de feedback : on utilise les évaluations de performance comme proxy.
-- Année de référence = année de params.ref_date. Colonne annexe : dernière année couverte par les données.
SELECT
    e.id_employe, e.nom, e.prenom, e.poste, e.nom_departement, e.manager,
    e.derniere_evaluation                                           AS derniere_evaluation_valide,
    CAST(julianday((SELECT ref_date FROM params)) - julianday(e.derniere_evaluation) AS INTEGER)
                                                                    AS jours_depuis_derniere_evaluation
FROM employes_enrichi e
WHERE e.statut = 'actif'
  AND NOT EXISTS (
        SELECT 1 FROM evaluations ev
        WHERE ev.id_employe = e.id_employe
          AND ev.annee = strftime('%Y', (SELECT ref_date FROM params)))
ORDER BY jours_depuis_derniere_evaluation DESC, e.id_employe;


-- @Q13b | Couverture du feedback : année de référence vs dernière année présente dans les données
SELECT
    (SELECT strftime('%Y', ref_date) FROM params)                          AS annee_reference,
    (SELECT MAX(annee) FROM evaluations)                                   AS derniere_annee_donnees,
    COUNT(*)                                                               AS employes_actifs,
    SUM(NOT EXISTS (SELECT 1 FROM evaluations ev WHERE ev.id_employe = e.id_employe
                    AND ev.annee = (SELECT strftime('%Y', ref_date) FROM params)))
                                                                           AS sans_feedback_annee_reference,
    SUM(NOT EXISTS (SELECT 1 FROM evaluations ev WHERE ev.id_employe = e.id_employe
                    AND ev.annee = (SELECT MAX(annee) FROM evaluations)))
                                                                           AS sans_feedback_derniere_annee_donnees,
    SUM(NOT EXISTS (SELECT 1 FROM evaluations ev WHERE ev.id_employe = e.id_employe
                    AND ev.annee = (SELECT MAX(annee) FROM evaluations)
                    AND ev.eval_valide = 1))
                                                                           AS sans_feedback_valide_derniere_annee
FROM employes_enrichi e
WHERE e.statut = 'actif';


-- @Q14a | Segmentation des employés par niveau de performance (faible / moyen / élevé)
SELECT
    categorie_performance,
    COUNT(*)                                             AS nb_employes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS pct_employes,
    ROUND(AVG(score_moyen), 2)                           AS score_moyen,
    ROUND(AVG(taux_objectifs_pct), 1)                    AS taux_objectifs_pct,
    ROUND(AVG(salaire), 0)                               AS salaire_moyen,
    SUM(est_parti)                                       AS dont_partis
FROM employes_enrichi
GROUP BY categorie_performance
ORDER BY CASE categorie_performance
             WHEN 'faible' THEN 1 WHEN 'moyen' THEN 2 WHEN 'élevé' THEN 3 ELSE 4 END;


-- @Q14b | Segmentation par département (nombre et % des employés évalués)
SELECT
    nom_departement,
    SUM(categorie_performance = 'faible')   AS faible,
    SUM(categorie_performance = 'moyen')    AS moyen,
    SUM(categorie_performance = 'élevé')    AS eleve,
    SUM(categorie_performance = 'non évalué (<4 évals)') AS non_evalue,
    ROUND(100.0 * SUM(categorie_performance = 'faible')
          / SUM(categorie_performance <> 'non évalué (<4 évals)'), 1) AS pct_faible,
    ROUND(100.0 * SUM(categorie_performance = 'moyen')
          / SUM(categorie_performance <> 'non évalué (<4 évals)'), 1) AS pct_moyen,
    ROUND(100.0 * SUM(categorie_performance = 'élevé')
          / SUM(categorie_performance <> 'non évalué (<4 évals)'), 1) AS pct_eleve
FROM employes_enrichi
GROUP BY nom_departement
ORDER BY pct_eleve DESC;


-- @Q15 | Tableau de synthèse : KPIs par département, par cohorte, croisés et global
-- Chaque employé est dupliqué sur 4 niveaux d'agrégation puis agrégé en une seule requête.
WITH lignes AS (
    SELECT 'Département × cohorte' AS niveau, nom_departement AS departement, cohorte_embauche AS cohorte, * FROM employes_enrichi
    UNION ALL
    SELECT 'Département',           nom_departement, 'Toutes',          * FROM employes_enrichi
    UNION ALL
    SELECT 'Cohorte',               'Tous',          cohorte_embauche,  * FROM employes_enrichi
    UNION ALL
    SELECT 'Global',                'Tous',          'Toutes',          * FROM employes_enrichi
)
SELECT
    niveau, departement, cohorte,
    COUNT(*)                                                           AS embauches,
    SUM(1 - est_parti)                                                 AS actifs,
    SUM(est_parti)                                                     AS departs_realises,
    ROUND(100.0 * SUM(1 - est_parti) / COUNT(*), 1)                    AS retention_pct,
    ROUND(100.0 * SUM(retenu_12m) / NULLIF(COUNT(retenu_12m), 0), 1)   AS retention_12m_pct,
    ROUND(100.0 * SUM(est_parti AND type_depart = 'volontaire')
          / NULLIF(SUM(est_parti), 0), 1)                              AS departs_volontaires_pct,
    ROUND(AVG(CASE WHEN est_parti = 0 THEN salaire END), 0)            AS salaire_moyen_actifs,
    ROUND(AVG(anciennete_ans), 2)                                      AS anciennete_moyenne_ans,
    ROUND(AVG(score_moyen), 2)                                         AS score_moyen,
    ROUND(AVG(taux_objectifs_pct), 1)                                  AS taux_objectifs_pct,
    ROUND(100.0 * SUM(categorie_performance = 'élevé')
          / NULLIF(SUM(categorie_performance <> 'non évalué (<4 évals)'), 0), 1) AS pct_perf_elevee,
    ROUND(100.0 * SUM(categorie_performance = 'faible')
          / NULLIF(SUM(categorie_performance <> 'non évalué (<4 évals)'), 0), 1) AS pct_perf_faible
FROM lignes
GROUP BY niveau, departement, cohorte
ORDER BY CASE niveau WHEN 'Global' THEN 1 WHEN 'Département' THEN 2 WHEN 'Cohorte' THEN 3 ELSE 4 END,
         departement, cohorte;
