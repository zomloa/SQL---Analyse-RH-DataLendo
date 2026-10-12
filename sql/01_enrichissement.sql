-- =====================================================================
-- 01_enrichissement.sql  |  Colonnes dérivées + dataset enrichi
-- Dépend de : 00_schema.sql + chargement des CSV + params.ref_date
--
-- Hypothèses structurantes (détail dans le README) :
--   H1  Date de référence = params.ref_date ("aujourd'hui").
--   H2  Un employé est PARTI si employes.date_depart <= ref_date.
--       Une date_depart postérieure à ref_date = départ PLANIFIÉ : l'employé
--       est encore actif à la date de référence.
--   H3  employes.date_depart est la source de vérité pour les dates et
--       l'ancienneté. turnover.date_depart et turnover.anciennete sont
--       incohérentes avec employes (voir README) : seul turnover.type_depart
--       est utilisé.
--   H4  Une évaluation n'est VALIDE que si elle tombe pendant la période
--       d'emploi (date_embauche <= date_evaluation <= date_depart éventuelle).
--   H5  Catégorie de performance : score moyen individuel sur évaluations
--       valides, avec au moins 4 évaluations (1 an).
--         faible < 70  |  moyen 70 à < 78  |  élevé >= 78
--       (seuils ~ P20 / P75 de la distribution observée)
-- =====================================================================

DROP TABLE IF EXISTS evaluations;
DROP TABLE IF EXISTS perf_employe;
DROP TABLE IF EXISTS employes_enrichi;

-- ---------------------------------------------------------------------
-- 1) Évaluations avec indicateur de validité et libellé de trimestre
-- ---------------------------------------------------------------------
CREATE TABLE evaluations AS
SELECT
    p.id_performance,
    p.id_employe,
    p.date_evaluation,
    strftime('%Y', p.date_evaluation) || '-T'
        || ((CAST(strftime('%m', p.date_evaluation) AS INTEGER) + 2) / 3)   AS trimestre,
    strftime('%Y', p.date_evaluation)                                         AS annee,
    p.score,
    p.objectifs_atteints,
    CASE WHEN p.date_evaluation >= e.date_embauche
          AND (e.date_depart IS NULL OR p.date_evaluation <= e.date_depart)
         THEN 1 ELSE 0 END                                                    AS eval_valide
FROM performances p
JOIN employes e ON e.id_employe = p.id_employe;

CREATE INDEX idx_eval_emp ON evaluations(id_employe);

-- ---------------------------------------------------------------------
-- 2) Synthèse de performance par employé (évaluations valides uniquement)
-- ---------------------------------------------------------------------
CREATE TABLE perf_employe AS
SELECT
    id_employe,
    COUNT(*)                                   AS nb_evals_valides,
    ROUND(AVG(score), 2)                       AS score_moyen,
    MIN(score)                                 AS score_min,
    MAX(score)                                 AS score_max,
    ROUND(100.0 * AVG(objectifs_atteints), 1)  AS taux_objectifs_pct,
    MAX(date_evaluation)                       AS derniere_evaluation,
    CASE
        WHEN COUNT(*) < 4      THEN 'non évalué (<4 évals)'
        WHEN AVG(score) < 70   THEN 'faible'
        WHEN AVG(score) < 78   THEN 'moyen'
        ELSE                        'élevé'
    END                                        AS categorie_performance
FROM evaluations
WHERE eval_valide = 1
GROUP BY id_employe;

CREATE INDEX idx_perfemp ON perf_employe(id_employe);

-- ---------------------------------------------------------------------
-- 3) Dataset enrichi : une ligne par employé
-- ---------------------------------------------------------------------
CREATE TABLE employes_enrichi AS
WITH base AS (
    SELECT
        e.id_employe, e.nom, e.prenom, e.poste,
        e.departement_id, d.nom_departement, d.manager,
        e.date_embauche, e.date_depart, e.salaire,
        r.ref_date,
        t.type_depart,
        t.date_depart AS date_depart_turnover,
        CASE WHEN e.date_depart IS NOT NULL AND e.date_depart <= r.ref_date
             THEN 1 ELSE 0 END AS est_parti
    FROM employes e
    JOIN departements d ON d.id_departement = e.departement_id
    CROSS JOIN params r
    LEFT JOIN turnover t ON t.id_employe = e.id_employe
),
calc AS (
    SELECT b.*,
        CASE WHEN est_parti = 1 THEN date_depart ELSE ref_date END AS date_fin_observation
    FROM base b
)
SELECT
    c.id_employe, c.nom, c.prenom, c.poste,
    c.departement_id, c.nom_departement, c.manager,
    c.date_embauche, c.date_depart, c.salaire,

    -- statut
    CASE WHEN c.est_parti = 1 THEN 'parti' ELSE 'actif' END                     AS statut,
    c.est_parti,
    CASE WHEN c.est_parti = 0 AND c.date_depart IS NOT NULL THEN 1 ELSE 0 END   AS depart_planifie,
    c.type_depart,
    strftime('%Y', CASE WHEN c.est_parti = 1 THEN c.date_depart END)            AS annee_depart,

    -- ancienneté (en années, à la date de départ ou à la date de référence)
    ROUND((julianday(c.date_fin_observation) - julianday(c.date_embauche)) / 365.25, 2)
                                                                                AS anciennete_ans,
    CASE
        WHEN (julianday(c.date_fin_observation) - julianday(c.date_embauche)) / 365.25 < 1 THEN '< 1 an'
        WHEN (julianday(c.date_fin_observation) - julianday(c.date_embauche)) / 365.25 < 3 THEN '1 à < 3 ans'
        WHEN (julianday(c.date_fin_observation) - julianday(c.date_embauche)) / 365.25 < 5 THEN '3 à < 5 ans'
        WHEN (julianday(c.date_fin_observation) - julianday(c.date_embauche)) / 365.25 < 7 THEN '5 à < 7 ans'
        ELSE '7 ans et +'
    END                                                                         AS tranche_anciennete,

    -- cohorte d'embauche
    strftime('%Y', c.date_embauche)                                             AS cohorte_embauche,

    -- rétention à 12 / 24 mois (NULL si la période n'est pas encore observable)
    CASE WHEN date(c.date_embauche, '+12 months') > c.ref_date THEN NULL
         WHEN c.date_depart IS NULL OR c.date_depart >= date(c.date_embauche, '+12 months')
         THEN 1 ELSE 0 END                                                      AS retenu_12m,
    CASE WHEN date(c.date_embauche, '+24 months') > c.ref_date THEN NULL
         WHEN c.date_depart IS NULL OR c.date_depart >= date(c.date_embauche, '+24 months')
         THEN 1 ELSE 0 END                                                      AS retenu_24m,

    -- performance
    COALESCE(p.nb_evals_valides, 0)                                             AS nb_evals_valides,
    p.score_moyen,
    p.taux_objectifs_pct,
    p.derniere_evaluation,
    COALESCE(p.categorie_performance, 'non évalué (<4 évals)')                  AS categorie_performance,

    -- traçabilité qualité de données
    (SELECT COUNT(*) FROM evaluations v
      WHERE v.id_employe = c.id_employe AND v.eval_valide = 0)                  AS nb_evals_hors_periode,
    c.date_depart_turnover,
    CASE WHEN c.date_depart_turnover IS NOT NULL
          AND c.date_depart_turnover <> c.date_depart THEN 1 ELSE 0 END         AS flag_date_turnover_incoherente
FROM calc c
LEFT JOIN perf_employe p ON p.id_employe = c.id_employe;

CREATE INDEX idx_enr_dept ON employes_enrichi(departement_id);
