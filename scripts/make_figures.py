"""Génère les graphiques du document d'insights. Usage : python scripts/make_figures.py <dossier_projet>  (après run_analysis.py)."""
import sys
from pathlib import Path
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(sys.argv[1]); OUT = ROOT / "outputs"; FIG = OUT / "figures"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
INK, MUTED, GRID = "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": MUTED,
                     "xtick.color": MUTED, "ytick.color": MUTED, "text.color": INK,
                     "axes.spines.top": False, "axes.spines.right": False, "figure.dpi": 100})

def clean(ax, axis="x"):
    ax.grid(axis=axis, color=GRID, linewidth=0.8); ax.set_axisbelow(True)

# 1. Turnover par département
q3 = pd.read_csv(OUT / "Q03.csv").sort_values("taux_turnover_pct")
glob = 100 * q3.departs_realises.sum() / q3.effectif_total_historique.sum()
fig, ax = plt.subplots(figsize=(7.2, 3.9))
ax.barh(q3.nom_departement, q3.taux_turnover_pct, color=BLUE, height=0.62)
for y, v in enumerate(q3.taux_turnover_pct): ax.text(v + 0.2, y, f"{v:.1f} %", va="center", color=INK, fontsize=9)
ax.axvline(glob, color=MUTED, linestyle="--", linewidth=1)
ax.set_ylim(-0.6, 10.0); ax.text(glob + 0.15, 9.65, f"moyenne {glob:.1f} %", color=MUTED, fontsize=8.5, va="center")
ax.set_xlim(0, 17); ax.set_xlabel("Départs réalisés / effectif total historique (%)"); clean(ax)
ax.set_title("Taux de turnover par département", loc="left", fontsize=11.5, fontweight="bold")
fig.tight_layout(); fig.savefig(FIG / "fig1_turnover_departement.png", dpi=170); plt.close(fig)

# 2. Rétention par cohorte
q9 = pd.read_csv(OUT / "Q09.csv"); q9 = q9[q9.cohorte_embauche != "Toutes cohortes"]
fig, ax = plt.subplots(figsize=(7.2, 3.6)); w = 0.26; xs = range(len(q9))
series = [("retention_12_mois_pct", "Rétention à 12 mois", BLUE), ("retention_24_mois_pct", "Rétention à 24 mois", ORANGE),
          ("retention_actuelle_pct", "Rétention actuelle", AQUA)]
for i, (col, lab, c) in enumerate(series):
    pos = [x + (i - 1) * (w + 0.02) for x in xs]
    ax.bar(pos, q9[col], width=w, color=c, label=lab)
    for p, v in zip(pos, q9[col]): ax.text(p, v + 0.6, f"{v:.0f}", ha="center", fontsize=8, color=INK)
ax.set_xticks(list(xs)); ax.set_xticklabels(q9.cohorte_embauche); ax.set_ylim(70, 104)
ax.set_ylabel("% d'employés (axe tronqué à 70 %)"); ax.set_xlabel("Cohorte d'embauche"); clean(ax, "y")
ax.legend(frameon=False, ncol=3, loc="upper center", bbox_to_anchor=(0.5, 1.02), fontsize=9)
fig.tight_layout(); fig.savefig(FIG / "fig2_retention_cohorte.png", dpi=170); plt.close(fig)

# 3. Segmentation performance par département (100 % empilé, séquentiel)
q14 = pd.read_csv(OUT / "Q14b.csv").sort_values("pct_eleve")
fig, ax = plt.subplots(figsize=(7.2, 3.9)); left = pd.Series(0.0, index=q14.index)
for col, lab, c in [("pct_faible", "Faible (< 70)", "#bcd6f4"), ("pct_moyen", "Moyen (70 à < 78)", "#6aa3e6"), ("pct_eleve", "Élevé (≥ 78)", "#1c4f94")]:
    ax.barh(q14.nom_departement, q14[col], left=left + 0.0, color=c, label=lab, height=0.62, edgecolor="white", linewidth=1.5)
    for y, (l, v) in enumerate(zip(left, q14[col])):
        ax.text(l + v / 2, y, f"{v:.0f}", ha="center", va="center", fontsize=8.5, color=INK if c == "#bcd6f4" else "white")
    left = left + q14[col]
ax.set_xlim(0, 100); ax.set_xlabel("% des employés évalués"); clean(ax, "x")
ax.legend(frameon=False, ncol=3, loc="upper center", bbox_to_anchor=(0.45, 1.09), fontsize=9)
fig.tight_layout(); fig.savefig(FIG / "fig3_segmentation_performance.png", dpi=170); plt.close(fig)

# 4. Départs réalisés par année et type
d = pd.read_csv(OUT / "dataset_enrichi.csv"); d = d[d.est_parti == 1]
pv = d.groupby(["annee_depart", "type_depart"]).size().unstack(fill_value=0)
pv.index = pv.index.astype(int)
fig, ax = plt.subplots(figsize=(7.2, 3.5)); bottom = pd.Series(0, index=pv.index)
for col, c in [("volontaire", BLUE), ("involontaire", ORANGE)]:
    ax.bar(pv.index.astype(str), pv[col], bottom=bottom, color=c, label=col.capitalize(), width=0.62, edgecolor="white", linewidth=1.5)
    bottom = bottom + pv[col]
for x, tot in zip(pv.index.astype(str), bottom): ax.text(x, tot + 0.8, int(tot), ha="center", fontsize=9)
ax.set_ylabel("Départs réalisés"); ax.set_xlabel("Année de départ (2026 : jusqu'au 10/10)"); clean(ax, "y")
ax.legend(frameon=False, loc="upper left", fontsize=9)
fig.tight_layout(); fig.savefig(FIG / "fig4_departs_par_annee.png", dpi=170); plt.close(fig)
print("ok", pv.sum().to_dict())
