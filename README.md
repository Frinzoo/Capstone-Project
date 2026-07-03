# Capstone Project — Analisi del mercato immobiliare residenziale italiano (2016-2025)

**Francesco Laganà** — Capstone Project per il Master in Data Analytics e Machine Learning, Epicode

---

## Il progetto

Questo repository raccoglie tutto il lavoro prodotto per il Capstone Project finale del Master Epicode.
L'obiettivo è analizzare come si sono mossi i prezzi delle abitazioni in sei province italiane
nel periodo 2016-2025, e costruire un modello di previsione per il primo semestre 2026.

Le sei province analizzate sono **Bologna, Milano, Napoli, Palermo, Roma e Torino**.
I dati riguardano esclusivamente abitazioni civili in stato normale, la tipologia
più rappresentativa del mercato residenziale italiano.

La previsione per il 2026 sarà verificabile a settembre 2026, quando l'Agenzia delle Entrate
pubblicherà il dato ufficiale OMI.

---

## Struttura del repository

```
capstone-epicode-immobiliare/
│
├── 0-docs/
│   └── Capstone_Project_Analisi_Mercato_Immobiliare.docx
│       Documento di riepilogo completo: obiettivi, fonti, metodologia,
│       risultati, modelli di previsione e limiti dell'analisi.
│
├── 1-data/
│   │
│   ├── external/                        Dati grezzi scaricati dalle fonti ufficiali
│   │   │                                (NON inclusi in questo repository — vedi sezione "Dati")
│   │   ├── Indice Prezzi abitazioni Istat - IBAB ISTAT/
│   │   │   └── Trimestrali dal 2010 (base 2025) ... .xlsx
│   │   │       Indice IPAB trimestrale ISTAT, base 2025=100
│   │   │
│   │   ├── Quotazioni immobiliari/       Dati OMI — Agenzia delle Entrate
│   │   │   └── zip/          Archivi originali scaricati dal portale OMI
│   │   │
│   │   ├── Tassi BCE/
│   │   │   └── tassi_rif_bce.xlsx
│   │   │       Tasso di rifinanziamento principale BCE, serie storica
│   │   │
│   │   └── Volumi di compravendita/     Dati VCN — Agenzia delle Entrate
│   │       └── zip/       Archivi originali scaricati dal portale OMI
│   │
│   ├── processed/                       Dataset elaborati e validati
│   │   ├── Dataset.xlsx                 Dataset finale pulito (41.864 righe)
│   │   └── Modello previsione.xlsx      Risultati e confronto modelli di previsione
│   │
│   └── raw/
│       └── QI_VCN_BCE_ISTAT.xlsx        Dataset grezzo unificato pre-pulizia
│
├── 2-sql/
│   └── Database_immobiliare.sql
│       Script SQL completo (1.109 righe): creazione database, import dati,
│       analisi (prezzo medio, variazione % con LAG, ranking con RANK),
│       viste annuali e semestrali, modello di regressione in puro SQL.
│       Sintassi MySQL 8.0+, ogni blocco commentato in italiano semplice.
│
├── 3-python/
│   ├── dashboard.py                     Dashboard Streamlit interattiva (5 schede)
│   ├── modello_sarimax.py               Modello SARIMAX con selezione automatica ordini
│   ├── dashboard_dataset.csv            ← NON incluso (vedi sezione "Dati")
│   ├── dashboard_previsioni.csv         Previsioni H1 2026 — regressione polinomiale
│   ├── dashboard_previsioni_sarimax.csv Previsioni H1 2026 — SARIMAX
│   ├── previsioni_sarimax.csv           Output dettagliato confronto modelli
│   ├── requirements_dashboard.txt       Dipendenze Python
│   └── README_dashboard.md              Istruzioni per avviare la dashboard
│
└── outputs/                             Risultati finali pronti alla consultazione
    ├── Capstone_Project_Analisi_Mercato_Immobiliare.docx
    ├── OMI_QI_VCN_BCE_ISTAT_FINALE.xlsx
    ├── Dati_Raw_OMI_VCN_BCE_ISTAT.xlsx
    ├── SQL_documentazione_query.xlsx
    ├── SQL_query_aggiuntive_risultati.xlsx
    ├── Modello_previsione_6_province.xlsx
    ├── Checklist_tecnica_progetto.xlsx
    └── ER_diagram_database.png
```

---

## Come avviare la dashboard

```bash
# 1. Vai nella cartella 3-python
cd 3-python

# 2. Installa le dipendenze (una volta sola)
pip install -r requirements_dashboard.txt

# 3. Avvia la dashboard
streamlit run dashboard.py
```

Si apre automaticamente nel browser su `http://localhost:8501`.
Funziona anche da smartphone se il computer è sulla stessa rete WiFi
(usare il Network URL mostrato nel terminale all'avvio).

---

## Come eseguire il modello SARIMAX

```bash
cd 3-python
pip install statsmodels
python3 modello_sarimax.py
```

Il modello testa automaticamente 6 combinazioni di parametri per ciascuna delle
6 province e sceglie quella con l'AIC più basso. L'output viene salvato in
`previsioni_sarimax.csv`.

---

## Come usare lo script SQL

1. Avviare MySQL (Workbench o terminale)
2. Modificare i percorsi `LOAD DATA LOCAL INFILE` nella Parte 2 con i percorsi
   reali dei file CSV sul proprio computer
3. Eseguire `SET GLOBAL local_infile = 1;` prima dello script
4. Eseguire `Database_immobiliare.sql` per intero

---

## Dati

I dati grezzi nella cartella `1-data/external/` provengono da fonti ufficiali pubbliche
e **non sono inclusi in questo repository**.

Per riprodurre l'analisi da zero:

- **Quotazioni OMI e VCN**: registrarsi al servizio Forniture dati OMI sul portale
  dell'Agenzia delle Entrate e scaricare i file QI e VCN per le province
  BO, MI, NA, PA, RM, TO, periodo 2016-2025.
  [agenziaentrate.gov.it](https://www.agenziaentrate.gov.it/portale/web/guest/schede/fabbricatiterreni/omi/banche-dati/quotazioni-immobiliari)

- **Indice IPAB**: disponibile pubblicamente su [istat.it](https://www.istat.it)

- **Tassi BCE**: disponibili pubblicamente su [ecb.europa.eu](https://www.ecb.europa.eu)

La pipeline di pulizia e unione dei dati è descritta nel documento in `0-docs/`
e negli script in `3-python/`.

> **Disclaimer**: tutti i dati sono stati utilizzati esclusivamente a fini accademici,
> senza alcuno scopo commerciale o di lucro.

---

## Stack tecnologico

| Strumento | Utilizzo |
|---|---|
| Python 3.x | Pulizia dati, modelli di previsione, dashboard |
| pandas, numpy | Manipolazione e analisi dei dati |
| scikit-learn | Regressione lineare e polinomiale |
| statsmodels | Modello SARIMAX |
| Streamlit + Plotly | Dashboard interattiva |
| MySQL 8.0+ | Database, analisi SQL, viste |
| Excel | Esplorazione dati, pivot, Data Quality Log |

---

## Risultati principali

| Provincia | Prezzo H2 2025 | Previsione H1 2026 | Modello scelto |
|---|---|---|---|
| Bologna | 1.676,6 €/mq | 1.703,7 €/mq | Regressione |
| Milano | 1.993,2 €/mq | 2.004,2 €/mq | SARIMAX (R²=0.848) |
| Napoli | 1.895,4 €/mq | 1.907,0 €/mq | Regressione |
| Palermo | 844,6 €/mq | 849,0 €/mq | Regressione |
| Roma | 2.032,4 €/mq | 2.054,5 €/mq | SARIMAX |
| Torino | 1.111,0 €/mq | 1.125,9 €/mq | Regressione |

La previsione sarà verificabile a settembre 2026 con la pubblicazione del dato
ufficiale OMI per il primo semestre 2026.

---

## Fonti

- Agenzia delle Entrate — OMI: agenziaentrate.gov.it
- ISTAT — Indice IPAB: istat.it
- Banca Centrale Europea: ecb.europa.eu
