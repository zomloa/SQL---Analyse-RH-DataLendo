-- =====================================================================
-- 00_schema.sql  |  Projet RH Analytics - DataLendo
-- Dialecte : SQLite 3.35+ (fonctions fenêtre, julianday, strftime)
-- Les CSV sont chargés par run_analysis.py (équivalent d'un COPY / BULK INSERT).
-- =====================================================================

DROP TABLE IF EXISTS performances;
DROP TABLE IF EXISTS turnover;
DROP TABLE IF EXISTS employes;
DROP TABLE IF EXISTS departements;
DROP TABLE IF EXISTS params;

-- Paramètre unique : la date de référence de l'analyse ("aujourd'hui").
-- Insérée par run_analysis.py (défaut : 2026-10-10). Tout le reste en dépend.
CREATE TABLE params (
    ref_date TEXT NOT NULL            -- format ISO AAAA-MM-JJ
);

CREATE TABLE departements (
    id_departement  INTEGER PRIMARY KEY,
    nom_departement TEXT    NOT NULL,
    manager         TEXT,
    budget          INTEGER
);

CREATE TABLE employes (
    id_employe      INTEGER PRIMARY KEY,
    nom             TEXT,
    prenom          TEXT,
    poste           TEXT,
    departement_id  INTEGER NOT NULL REFERENCES departements(id_departement),
    date_embauche   TEXT    NOT NULL,
    date_depart     TEXT,             -- NULL = pas de départ enregistré
    salaire         INTEGER
);

CREATE TABLE performances (
    id_performance     INTEGER PRIMARY KEY,
    id_employe         INTEGER NOT NULL REFERENCES employes(id_employe),
    date_evaluation    TEXT    NOT NULL,
    score              INTEGER NOT NULL,   -- 50 à 99
    objectifs_atteints INTEGER NOT NULL    -- 1 = True, 0 = False
);

CREATE TABLE turnover (
    id_depart    INTEGER PRIMARY KEY,
    id_employe   INTEGER NOT NULL REFERENCES employes(id_employe),
    date_depart  TEXT,                -- NON FIABLE (voir README, section qualité)
    type_depart  TEXT,                -- 'volontaire' | 'involontaire'
    anciennete   INTEGER              -- NON FIABLE (recalculée dans 01_enrichissement.sql)
);

CREATE INDEX idx_emp_dept   ON employes(departement_id);
CREATE INDEX idx_perf_emp   ON performances(id_employe);
CREATE INDEX idx_perf_date  ON performances(date_evaluation);
CREATE INDEX idx_turn_emp   ON turnover(id_employe);
