"""
modello_sarimax.py

Modello di previsione SARIMAX per il prezzo medio delle abitazioni
nelle 6 province italiane (BO, MI, NA, PA, RM, TO), periodo 2016-2025.
Previsione: primo semestre 2026.

Per eseguirlo:
    pip install statsmodels
    python3 modello_sarimax.py

Il file legge 'dashboard_dataset.csv' (nella stessa cartella) e produce:
    - previsioni_sarimax.csv   (risultati da usare nella dashboard)
    - stampa a video un confronto tra SARIMAX e regressione precedente

Dipendenze:
    pip install statsmodels pandas numpy
"""

import warnings
warnings.filterwarnings('ignore')  # nascondiamo i warning tecnici di statsmodels

import numpy as np
import pandas as pd
from statsmodels.tsa.statespace.sarimax import SARIMAX
from sklearn.linear_model import LinearRegression
from sklearn.preprocessing import PolynomialFeatures
from sklearn.metrics import mean_absolute_error, r2_score


# =========================================================================
# CONFIGURAZIONE
# =========================================================================

# Le 6 province e i loro nomi per esteso
province = {
    'BO': 'Bologna',
    'MI': 'Milano',
    'NA': 'Napoli',
    'PA': 'Palermo',
    'RM': 'Roma',
    'TO': 'Torino',
}

# Valori stimati di ISTAT e BCE per il primo semestre 2026
# (usati come variabili esogene nella previsione)
IPAB_2026_S1 = 103.12
BCE_2026_S1 = 2.158

# Ultimi 4 semestri come holdout (test set) per valutare il modello
N_TEST = 4

# Ordini SARIMAX da provare: (p, d, q)(P, D, Q, s)
# Usiamo ordini piccoli per non sprecare gradi di liberta' con soli 20 punti
# s=2 perche' abbiamo 2 semestri per anno (la stagionalita')
ORDINI_DA_PROVARE = [
    ((1,1,0),(1,0,0,2)),
    ((1,1,1),(1,0,0,2)),
    ((0,1,1),(0,1,0,2)),
    ((1,1,1),(0,1,1,2)),
    ((1,1,0),(0,0,0,2)),
    ((0,1,1),(1,0,1,2)),
]


# =========================================================================
# CARICAMENTO DATI
# =========================================================================

print("Caricamento dati...")
df = pd.read_csv(
    'dashboard_dataset.csv',
    sep=';',
    keep_default_na=False,
    na_values=[''],
)
print(f"Righe caricate: {len(df)} | Province: {sorted(df['Prov'].unique())}\n")


# =========================================================================
# FUNZIONE: prepara la serie di una provincia
# =========================================================================

def prepara_serie(df, prov):
    """
    Raggruppa i dati per Anno e Semestre, calcola la media del prezzo
    e delle variabili macro, e restituisce un DataFrame ordinato.
    """
    serie = df[df['Prov'] == prov].groupby(['Anno', 'Semestre'], as_index=False).agg(
        Prezzo_medio_mq=('Prezzo_medio_mq', 'mean'),
        IPAB=('IPAB_tutte_voci', 'first'),
        BCE=('Tasso_BCE_medio_pct', 'first'),
    )
    serie = serie.sort_values(['Anno', 'Semestre']).reset_index(drop=True)
    return serie


# =========================================================================
# FUNZIONE: trova il miglior ordine SARIMAX (quello con AIC piu' basso)
# =========================================================================

def trova_miglior_ordine(y_train, esogene_train, ordini):
    """
    Prova tutti gli ordini SARIMAX nella lista e sceglie quello con
    il valore AIC piu' basso (Akaike Information Criterion: misura
    quanto il modello e' buono senza essere troppo complicato).
    """
    miglior_aic = float('inf')
    miglior_ordine = None
    miglior_ordine_stagionale = None

    for ordine, ordine_stagionale in ordini:
        try:
            modello = SARIMAX(
                y_train,
                exog=esogene_train,
                order=ordine,
                seasonal_order=ordine_stagionale,
                enforce_stationarity=False,
                enforce_invertibility=False,
            )
            risultato = modello.fit(disp=False)
            if risultato.aic < miglior_aic:
                miglior_aic = risultato.aic
                miglior_ordine = ordine
                miglior_ordine_stagionale = ordine_stagionale
        except Exception:
            continue

    return miglior_ordine, miglior_ordine_stagionale, miglior_aic


# =========================================================================
# FUNZIONE: modello di regressione (per confronto)
# =========================================================================

def regressione_polinomiale(serie, n_test):
    """
    Riproduce il vecchio modello (regressione polinomiale grado 2 + IPAB + BCE)
    per confrontarlo con SARIMAX. Restituisce R2 e MAE sul test set.
    """
    serie['t'] = range(1, len(serie) + 1)
    X = serie[['t', 'IPAB', 'BCE']].values
    y = serie['Prezzo_medio_mq'].values

    X_train, X_test = X[:-n_test], X[-n_test:]
    y_train, y_test = y[:-n_test], y[-n_test:]

    poly = PolynomialFeatures(degree=2, include_bias=False)
    X_train_poly = np.column_stack([poly.fit_transform(X_train[:, [0]]), X_train[:, 1:]])
    X_test_poly = np.column_stack([poly.transform(X_test[:, [0]]), X_test[:, 1:]])

    modello = LinearRegression().fit(X_train_poly, y_train)
    pred = modello.predict(X_test_poly)

    return r2_score(y_test, pred), mean_absolute_error(y_test, pred)


# =========================================================================
# CICLO PRINCIPALE: SARIMAX per ogni provincia
# =========================================================================

print("=" * 70)
print(f"{'Provincia':<12} {'Modello SARIMAX':<20} {'R2 SARIMAX':>10} {'MAE SARIMAX':>12} {'R2 Regressione':>14} {'Previsione H1 2026':>18}")
print("=" * 70)

risultati = []

for sigla, nome in province.items():

    serie = prepara_serie(df, sigla)

    y = serie['Prezzo_medio_mq'].values
    esogene = serie[['IPAB', 'BCE']].values

    # Dividiamo in train (primi 16 semestri) e test (ultimi 4)
    y_train = y[:-N_TEST]
    y_test  = y[-N_TEST:]
    esogene_train = esogene[:-N_TEST]
    esogene_test  = esogene[-N_TEST:]

    # Troviamo il miglior ordine SARIMAX
    ordine, ordine_stagionale, aic = trova_miglior_ordine(
        y_train, esogene_train, ORDINI_DA_PROVARE
    )

    if ordine is None:
        print(f"{nome:<12} NESSUN ORDINE VALIDO TROVATO")
        continue

    # Alleniamo il modello scelto sul train set e valutiamo sul test
    modello_test = SARIMAX(
        y_train,
        exog=esogene_train,
        order=ordine,
        seasonal_order=ordine_stagionale,
        enforce_stationarity=False,
        enforce_invertibility=False,
    ).fit(disp=False)

    pred_test = modello_test.forecast(steps=N_TEST, exog=esogene_test)
    r2_sarimax  = r2_score(y_test, pred_test)
    mae_sarimax = mean_absolute_error(y_test, pred_test)

    # Ora alleniamo il modello finale su TUTTA la serie (20 punti) per la previsione
    modello_finale = SARIMAX(
        y,
        exog=esogene,
        order=ordine,
        seasonal_order=ordine_stagionale,
        enforce_stationarity=False,
        enforce_invertibility=False,
    ).fit(disp=False)

    # Previsione H1 2026 (1 passo avanti, t=21)
    esogene_2026 = np.array([[IPAB_2026_S1, BCE_2026_S1]])
    previsione_2026 = modello_finale.forecast(steps=1, exog=esogene_2026)[0]

    # Vecchio modello per confronto
    r2_vecchio, mae_vecchio = regressione_polinomiale(serie.copy(), N_TEST)

    label_ordine = f"SARIMA{ordine}{ordine_stagionale}"

    print(
        f"{nome:<12} {label_ordine:<20} "
        f"{r2_sarimax:>10.3f} {mae_sarimax:>12.1f} "
        f"{r2_vecchio:>14.3f} "
        f"{previsione_2026:>18.1f} euro/mq"
    )

    risultati.append({
        'Provincia': sigla,
        'Citta_capoluogo': nome,
        'Ordine_SARIMAX': label_ordine,
        'AIC': round(aic, 2),
        'R2_SARIMAX_test': round(r2_sarimax, 3),
        'MAE_SARIMAX_test': round(mae_sarimax, 1),
        'R2_Regressione_test': round(r2_vecchio, 3),
        'Prezzo_H2_2025': round(y[-1], 1),
        'Prezzo_Previsto_H1_2026_SARIMAX': round(previsione_2026, 1),
        'Variazione_pct': round((previsione_2026 / y[-1] - 1) * 100, 2),
    })

print("=" * 70)

# Salviamo i risultati
risultati_df = pd.DataFrame(risultati)
risultati_df.to_csv('previsioni_sarimax.csv', sep=';', index=False)
print(f"\nRisultati salvati in previsioni_sarimax.csv")
print("\nRiepilogo finale:")
print(risultati_df[['Citta_capoluogo','R2_SARIMAX_test','R2_Regressione_test','Prezzo_Previsto_H1_2026_SARIMAX']].to_string(index=False))
