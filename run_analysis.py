"""Projet RH Analytics - DataLendo.

Charge les 4 CSV dans SQLite, exécute les scripts SQL du dossier sql/ et exporte
les résultats (outputs/*.csv, outputs/resultats_analyses.xlsx, outputs/dataset_enrichi.csv).

Usage :  python run_analysis.py [--ref-date AAAA-MM-JJ]
"""
import argparse
import csv
import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"
OUT_DIR = ROOT / "outputs"
DB_PATH = OUT_DIR / "rh_datalendo.db"
DEFAULT_REF_DATE = "2026-10-10"

TABLES = {
    # table : (fichier csv, colonnes dans l'ordre du CREATE TABLE)
    "departements": ("departements.csv", ["id_departement", "nom_departement", "manager", "budget"]),
    "employes": ("employes.csv", ["id_employe", "nom", "prenom", "poste", "departement_id",
                                  "date_embauche", "date_depart", "salaire"]),
    "performances": ("performances.csv", ["id_performance", "id_employe", "date_evaluation",
                                          "score", "objectifs_atteints"]),
    "turnover": ("turnover.csv", ["id_depart", "id_employe", "date_depart", "type_depart", "anciennete"]),
}


def load_csv(con, table, filename, columns):
    with open(ROOT / filename, newline="", encoding="utf-8") as f:
        rows = []
        for r in csv.DictReader(f):
            vals = []
            for c in columns:
                v = r[c].strip()
                if v == "":
                    v = None                      # cellule vide -> NULL
                elif c == "objectifs_atteints":
                    v = 1 if v.lower() == "true" else 0
                vals.append(v)
            rows.append(vals)
    marks = ",".join("?" * len(columns))
    con.executemany(f"INSERT INTO {table} ({','.join(columns)}) VALUES ({marks})", rows)
    return len(rows)


def split_queries(sql_text):
    """Découpe 02_analyses.sql en blocs {'Q01': (titre, requête)}."""
    parts = re.split(r"^-- @(Q\d+[a-z]?)\s*\|\s*(.*)$", sql_text, flags=re.M)
    return {parts[i]: (parts[i + 1].strip(), parts[i + 2].strip()) for i in range(1, len(parts), 3)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref-date", default=DEFAULT_REF_DATE, help="date de référence (ISO)")
    args = ap.parse_args()

    OUT_DIR.mkdir(exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()
    con = sqlite3.connect(DB_PATH)

    con.executescript((SQL_DIR / "00_schema.sql").read_text(encoding="utf-8"))
    con.execute("INSERT INTO params (ref_date) VALUES (?)", (args.ref_date,))
    for table, (fname, cols) in TABLES.items():
        print(f"  {table:<13} {load_csv(con, table, fname, cols):>6} lignes")
    con.commit()

    con.executescript((SQL_DIR / "01_enrichissement.sql").read_text(encoding="utf-8"))

    queries = split_queries((SQL_DIR / "02_analyses.sql").read_text(encoding="utf-8"))
    results = {}
    for key, (title, query) in queries.items():
        df = pd.read_sql_query(query, con)
        df.to_csv(OUT_DIR / f"{key}.csv", index=False, encoding="utf-8-sig")
        results[key] = df
        print(f"  {key:<5} {len(df):>5} lignes  | {title}")

    enrichi = pd.read_sql_query("SELECT * FROM employes_enrichi ORDER BY id_employe", con)
    enrichi.to_csv(OUT_DIR / "dataset_enrichi.csv", index=False, encoding="utf-8-sig")
    print(f"  dataset_enrichi {len(enrichi)} lignes x {enrichi.shape[1]} colonnes")

    with pd.ExcelWriter(OUT_DIR / "resultats_analyses.xlsx") as xl:
        enrichi.to_excel(xl, sheet_name="dataset_enrichi", index=False)
        for key, df in results.items():
            df.to_excel(xl, sheet_name=key, index=False)
    con.close()
    print(f"Terminé - date de référence {args.ref_date} - résultats dans {OUT_DIR}")


if __name__ == "__main__":
    main()
