"""
dashboard.py — Analisi mercato immobiliare italiano 2016-2025
Tesi di Master in Data Analytics e ML - Epicode
Avvio: streamlit run dashboard.py
"""

import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import streamlit as st

# =========================================================================
# CONFIGURAZIONE PAGINA
# =========================================================================
st.set_page_config(
    page_title="Analisi mercato immobiliare italiano 2016-2025",
    layout="wide",
    initial_sidebar_state="expanded",
)

# =========================================================================
# PALETTE COLORI
# =========================================================================
BG    = "#1B2A4A"
BG2   = "#243655"
ACC   = "#00C2E0"
ACC2  = "#FFD166"
WHITE = "#FFFFFF"
LGRAY = "#A8BFDB"

COLORI = {
    "BO": "#00C2E0", "MI": "#FFD166", "NA": "#06D6A0",
    "PA": "#EF476F", "RM": "#8B9FF4", "TO": "#F4A261",
}
NOMI = {
    "BO":"Bologna","MI":"Milano","NA":"Napoli",
    "PA":"Palermo","RM":"Roma","TO":"Torino",
}
COORDS = {
    "BO":(44.494887,11.342616), "MI":(45.464664,9.188540),
    "NA":(40.853294,14.268460), "PA":(38.115688,13.361267),
    "RM":(41.902784,12.496366), "TO":(45.070312,7.686856),
}
EVENTI = [
    (2020,"S1","Covid-19"),(2021,"S1","Superbonus"),
    (2022,"S2","Rialzo BCE"),(2023,"S2","Picco tassi"),(2025,"S1","Taglio tassi"),
]

# Motivazioni modello per ogni provincia (in linguaggio semplice)
# previsione_scelta = modello scelto | previsione_alt = modello alternativo
MOTIVAZIONI = {
    "BO": {
        "modello": "Regressione",
        "previsione": 1703.7,
        "variazione": +1.62,
        "previsione_alt": 1711.5,
        "motivo": (
            "Bologna ha un andamento molto regolare: i prezzi sono scesi "
            "gradualmente fino al 2019 e poi risaliti in modo costante. "
            "Una formula matematica semplice descrive bene questa curva stabile, "
            "mentre SARIMAX tende a sovrastimare le variazioni su serie così piatte."
        ),
        "affidabilita": "Media — R² = 0.07",
        "colore": "#00C2E0",
    },
    "MI": {
        "modello": "SARIMAX",
        "previsione": 2004.2,
        "variazione": +0.52,
        "previsione_alt": 2003.5,
        "motivo": (
            "Milano è la provincia con la crescita più accelerata degli ultimi anni: "
            "+382 euro/mq nel decennio, con un'impennata marcata dal 2022. "
            "SARIMAX impara che 'se il prezzo è salito questo semestre, tende a "
            "salire anche il prossimo', cogliendo il momentum in atto. "
            "Risultato: R² = 0.848, il più alto tra tutte le province."
        ),
        "affidabilita": "Alta — R² = 0.848",
        "colore": "#FFD166",
    },
    "NA": {
        "modello": "Regressione",
        "previsione": 1907.0,
        "variazione": +0.61,
        "previsione_alt": 1905.1,
        "motivo": (
            "Napoli ha subito un doppio shock: un crollo brusco nel 2020 (Covid) "
            "seguito da un rimbalzo nel 2021-2022. Questi due cambi di direzione "
            "ravvicinati confondono SARIMAX, che finisce per amplificarli invece "
            "di smorzarli. La regressione, pur imperfetta, produce stime più stabili."
        ),
        "affidabilita": "Bassa — entrambi i modelli faticano su questa serie",
        "colore": "#06D6A0",
    },
    "PA": {
        "modello": "Regressione",
        "previsione": 849.0,
        "variazione": +0.51,
        "previsione_alt": 852.9,
        "motivo": (
            "Palermo è il mercato più stabile: i prezzi oscillano in un range "
            "ristretto per tutto il decennio, senza trend forti né shock. "
            "Con così poca variazione da modellare, SARIMAX va in overfitting: "
            "impara oscillazioni casuali invece di un pattern reale. "
            "La regressione semplice è più prudente."
        ),
        "affidabilita": "Bassa — mercato troppo stabile per entrambi i modelli",
        "colore": "#EF476F",
    },
    "RM": {
        "modello": "SARIMAX",
        "previsione": 2054.5,
        "variazione": -0.69,
        "previsione_alt": 2018.4,
        "motivo": (
            "Roma ha un andamento a 'V': discesa continua dal 2016 al 2021, "
            "poi risalita decisa fino al 2025. SARIMAX coglie che negli ultimi "
            "semestri i prezzi stanno salendo con costanza e proietta questa "
            "tendenza in avanti. La regressione, allenata anche sugli anni di calo, "
            "sottostima la ripresa recente."
        ),
        "affidabilita": "Media — R² = -2.4 (migliore disponibile)",
        "colore": "#8B9FF4",
    },
    "TO": {
        "modello": "Regressione",
        "previsione": 1125.9,
        "variazione": +1.34,
        "previsione_alt": 1110.1,
        "motivo": (
            "Torino è il caso più difficile: i prezzi oscillano di pochi euro "
            "per 10 anni senza una direzione chiara (-35 euro/mq il trend totale). "
            "SARIMAX va in overfitting grave (R² = -184): con così poco segnale, "
            "il modello 'memorizza' le micro-oscillazioni invece di imparare un pattern. "
            "La regressione, pur con R² basso, è più conservativa e affidabile."
        ),
        "affidabilita": "Bassa — serie troppo piatta e volatile per entrambi i modelli",
        "colore": "#F4A261",
    },
}

# =========================================================================
# CSS GLOBALE — sidebar uniforme al resto della dashboard
# =========================================================================
st.markdown(f"""
<style>
  .stApp {{ background-color: {BG}; }}
  .stApp, .stApp p, .stApp li, .stMarkdown {{ color: {WHITE} !important; }}

  h1 {{ color:{WHITE}; font-family:Georgia,serif; font-weight:700;
        border-bottom:2px solid {ACC}; padding-bottom:10px; }}
  h2 {{ color:{ACC}; font-family:Georgia,serif; }}
  h3 {{ color:{LGRAY}; font-family:Georgia,serif; }}

  /* Sidebar stessa palette della dashboard */
  section[data-testid="stSidebar"] {{
    background-color:{BG2};
    border-right:2px solid {ACC};
  }}
  section[data-testid="stSidebar"] * {{ color:{WHITE} !important; }}

  button[data-baseweb="tab"] {{
    font-size:15px; font-weight:600; color:{LGRAY} !important;
  }}
  button[data-baseweb="tab"][aria-selected="true"] {{
    color:{WHITE} !important; border-bottom:3px solid {ACC};
  }}

  div[data-testid="stMetric"] {{
    background-color:{BG2}; border:1px solid {ACC};
    border-left:5px solid {ACC}; border-radius:10px; padding:18px;
  }}
  div[data-testid="stMetric"] * {{ color:{WHITE} !important; }}
  div[data-testid="stMetricValue"] {{ color:{ACC2} !important; font-size:2rem; }}

  div[data-testid="stDataFrame"] {{ border:1px solid {ACC}; border-radius:8px; }}
  details summary {{ color:{BG} !important; font-weight:600; }}
  details {{ background-color:{LGRAY}; border-radius:6px; padding:4px 8px; margin:4px 0; }}
  details[open] {{ background-color:{WHITE}; }}

  .caption-box {{
    background-color:{BG2}; border-left:4px solid {ACC};
    border-radius:6px; padding:12px 16px; margin:8px 0 16px 0;
    color:{LGRAY}; font-style:italic; font-size:14px;
  }}

  /* Card provincia previsione */
  .provincia-card {{
    background-color:{BG2}; border:1px solid {ACC};
    border-radius:10px; padding:18px; margin-bottom:12px;
  }}

  /* Disclaimer */
  .disclaimer-box {{
    background-color:{BG2}; border:1px solid {ACC2};
    border-left:5px solid {ACC2}; border-radius:8px;
    padding:14px 18px; margin:16px 0;
    color:{LGRAY}; font-size:13px;
  }}
</style>
""", unsafe_allow_html=True)

def caption(testo):
    st.markdown(f'<div class="caption-box">{testo}</div>', unsafe_allow_html=True)

def layout_grafico(fig, height=480, title=None):
    fig.update_layout(
        height=height, plot_bgcolor=BG2, paper_bgcolor=BG,
        font=dict(color=WHITE, family="Georgia,serif"),
        title=dict(text=title, font=dict(size=15, color=LGRAY)) if title else None,
        legend=dict(bgcolor=BG2, bordercolor=ACC, borderwidth=1,
                    font=dict(color=WHITE)),
        xaxis=dict(gridcolor="#2E4470", linecolor=ACC, tickfont=dict(color=LGRAY)),
        yaxis=dict(gridcolor="#2E4470", linecolor=ACC, tickfont=dict(color=LGRAY)),
        margin=dict(l=50, r=30, t=50 if title else 30, b=50),
    )
    return fig

# =========================================================================
# CARICAMENTO DATI
# =========================================================================
@st.cache_data
def carica():
    df = pd.read_csv("dashboard_dataset.csv", sep=";",
                     keep_default_na=False, na_values=[""])
    prev = pd.read_csv("dashboard_previsioni.csv", sep=";",
                       keep_default_na=False, na_values=[""])
    sar  = pd.read_csv("dashboard_previsioni_sarimax.csv", sep=";",
                       keep_default_na=False, na_values=[""])
    df["Citta"]   = df["Prov"].map(NOMI)
    df["Periodo"] = df["Anno"].astype(str) + " " + df["Semestre"]
    return df, prev, sar

df, prev, sarimax = carica()

# =========================================================================
# SIDEBAR
# =========================================================================
st.sidebar.title("Filtri")
st.sidebar.markdown("---")

province_scelte = st.sidebar.multiselect(
    "Province",
    options=sorted(df["Prov"].unique()),
    default=sorted(df["Prov"].unique()),
    format_func=lambda s: NOMI[s] + " (" + s + ")",
)
anno_range = st.sidebar.slider(
    "Periodo", min_value=2016, max_value=2025, value=(2016, 2025)
)
solo_capoluogo = st.sidebar.checkbox("Solo comuni capoluogo", value=False)
st.sidebar.markdown("---")
st.sidebar.caption("Fonti: Agenzia Entrate (OMI), ISTAT, BCE.")

# Filtro dati
dati = df[df["Prov"].isin(province_scelte)]
dati = dati[(dati["Anno"] >= anno_range[0]) & (dati["Anno"] <= anno_range[1])]
if solo_capoluogo:
    dati = dati[dati["Comune_descrizione"].isin(
        ["BOLOGNA","MILANO","NAPOLI","PALERMO","ROMA","TORINO"]
    )]
if len(dati) == 0:
    st.warning("Nessun dato con i filtri selezionati.")
    st.stop()

# =========================================================================
# INTESTAZIONE
# =========================================================================
st.title("Analisi mercato immobiliare italiano 2016-2025")
st.markdown(
    "La dashboard mostra un'analisi predittiva del mercato italiano nel 2026 "
    "attraverso i dati degli ultimi 10 anni."
)

# =========================================================================
# SCHEDE
# =========================================================================
tab0, tab1, tab2, tab3, tab4 = st.tabs([
    "Introduzione",
    "10 anni di dati",
    "Dati utilizzati",
    "Dove e quanto",
    "Previsione 2026",
])


# =========================================================================
# SCHEDA 0 — INTRODUZIONE
# =========================================================================
with tab0:

    st.header("Capstone Project EPICODE di Francesco Laganà")
    st.markdown(
        "Questo progetto è l'elaborato finale del Master in Data Analytics di EPICODE. "
        "Raccoglie e analizza i dati ufficiali del mercato immobiliare italiano nel "
        "periodo **2016-2025**, con l'obiettivo di costruire un modello di previsione "
        "per il primo semestre del **2026**."
    )

    st.write("")

    st.markdown("""
### Contenuto delle pagine

- **10 anni di dati** — come sono cambiati i prezzi delle case e il numero di
  compravendite dal 2016 al 2025, con i principali eventi storici evidenziati
  direttamente sui grafici (Covid, Superbonus, rialzo tassi BCE)

- **Dati utilizzati** — le tre fonti ufficiali usate nell'analisi: le quotazioni
  dell'Agenzia delle Entrate, l'indice dei prezzi ISTAT e i tassi della Banca
  Centrale Europea. I dati sono consultabili per intero in formato tabella

- **Dove e quanto** — una mappa delle sei province analizzate con l'intensità del
  prezzo, una heatmap anno per anno, e un grafico interattivo che posiziona ogni
  provincia nel suo "quadrante di mercato"

- **Previsione 2026** — la stima del prezzo medio al metro quadro per il primo
  semestre 2026 in ciascuna delle sei province, calcolata con due modelli statistici
  diversi e spiegata in modo semplice

---

### Note metodologiche

L'analisi copre le province di **Bologna, Milano, Napoli, Palermo, Roma e Torino**,
selezionate per rappresentare aree geografiche, dimensioni di mercato e dinamiche di
prezzo diverse. I dati si riferiscono esclusivamente ad **abitazioni civili in stato
normale**, tipologia prevalente nel mercato residenziale italiano.

La previsione per il 2026 è una stima statistica basata su dati storici: non tiene conto
di eventi futuri imprevedibili (nuove politiche fiscali, shock economici, pandemie).
Va letta come un'indicazione di tendenza, non come un valore certo.

---

### Le sei province analizzate
""")

    # Mini card province
    cols_intro = st.columns(6)
    for i, (prov, nome) in enumerate(NOMI.items()):
        if prov in province_scelte:
            prezzo_recente = dati[dati["Prov"] == prov]["Prezzo_medio_mq"].mean()
            cols_intro[i].metric(nome, f"{prezzo_recente:,.0f} €/mq")

    st.markdown("---")

    st.markdown("""
### Glossario dei termini principali

| Termine | Significato |
|---|---|
| **€/mq** | Euro al metro quadro, il prezzo di riferimento per le abitazioni |
| **NTN** | Numero di Transazioni Normalizzate: quante case sono state comprate e vendute |
| **OMI** | Osservatorio del Mercato Immobiliare dell'Agenzia delle Entrate |
| **IPAB** | Indice dei Prezzi delle Abitazioni pubblicato dall'ISTAT (base 100 = anno 2025) |
| **Tasso BCE** | Il tasso di interesse fissato dalla Banca Centrale Europea, che influenza il costo dei mutui |
| **Fascia OMI** | Zona della città secondo la classificazione dell'Agenzia delle Entrate (B=semicentrale, C=periferica, D=suburbana, E=rurale, R=centro) |
| **SARIMAX** | Modello statistico avanzato per serie temporali, spiega sotto nella scheda Previsione |
| **R²** | Indice di affidabilità del modello: vicino a 1 = ottimo, vicino a 0 = scarso, negativo = peggio di una media |
""")




# =========================================================================
# SCHEDA 1 — 10 ANNI DI DATI
# =========================================================================
with tab1:

    ultimo = dati[dati["Anno"] == dati["Anno"].max()]
    primo  = dati[dati["Anno"] == dati["Anno"].min()]
    prezzo_oggi   = ultimo["Prezzo_medio_mq"].mean()
    prezzo_inizio = primo["Prezzo_medio_mq"].mean()
    variazione    = (prezzo_oggi / prezzo_inizio - 1) * 100
    ntn_oggi      = ultimo["NTN Totale"].mean()
    bce_oggi      = ultimo["Tasso_BCE_medio_pct"].mean()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Province analizzate", len(province_scelte))
    c2.metric("Prezzo medio 2025", f"{prezzo_oggi:,.0f} €/mq",
              f"{variazione:+.1f}% dal {anno_range[0]}")
    c3.metric("Compravendite medie 2025", f"{ntn_oggi:,.0f} NTN")
    c4.metric("Tasso BCE 2025", f"{bce_oggi:.2f}%", "-1.7% dal picco 2024")

    st.write("")
    st.subheader("L'andamento dei prezzi 2016-2025")

    serie_sem = dati.groupby(
        ["Prov","Anno","Semestre","Periodo"], as_index=False
    )["Prezzo_medio_mq"].mean().sort_values(["Anno","Semestre"])
    serie_sem["Citta"] = serie_sem["Prov"].map(NOMI)

    fig1 = px.line(
        serie_sem, x="Periodo", y="Prezzo_medio_mq",
        color="Prov", color_discrete_map=COLORI, markers=True,
        labels={"Prezzo_medio_mq":"Euro/mq","Periodo":""},
        hover_data={"Citta": True},
    )
    for anno, sem, label in EVENTI:
        periodo_label = f"{anno} {sem}"
        prezzi_p = serie_sem[serie_sem["Periodo"] == periodo_label]["Prezzo_medio_mq"]
        if len(prezzi_p) > 0:
            y_pos = prezzi_p.max() + 60
            fig1.add_vline(x=periodo_label, line_dash="dot",
                           line_color=ACC, line_width=1, opacity=0.6)
            fig1.add_annotation(x=periodo_label, y=y_pos, text=label,
                showarrow=False, font=dict(color=ACC2, size=11),
                bgcolor=BG2, bordercolor=ACC, borderwidth=1)
    fig1 = layout_grafico(fig1, height=500)
    fig1.update_xaxes(tickangle=-45, tickfont=dict(size=10, color=LGRAY))
    st.plotly_chart(fig1, use_container_width=True)
    caption(
        "Le linee colorate mostrano l'andamento del prezzo medio al metro quadro "
        "semestre per semestre. Le linee tratteggiate verticali segnalano eventi "
        "importanti che hanno influenzato il mercato: il Covid nel 2020 ha causato "
        "un calo temporaneo; il Superbonus 110% nel 2021 ha rilanciato le compravendite; "
        "il rialzo dei tassi BCE dal 2022 ha frenato la domanda ma non i prezzi."
    )

    st.write("")
    st.subheader("Prezzo e compravendite: due storie diverse")

    serie_anno = dati.groupby("Anno", as_index=False).agg(
        Prezzo=("Prezzo_medio_mq","mean"),
        NTN=("NTN Totale","mean"),
    )
    fig2 = make_subplots(specs=[[{"secondary_y": True}]])
    fig2.add_trace(go.Scatter(
        x=serie_anno["Anno"], y=serie_anno["Prezzo"],
        name="Prezzo medio (€/mq)", mode="lines+markers",
        line=dict(color=ACC, width=3), marker=dict(size=8),
    ), secondary_y=False)
    fig2.add_trace(go.Bar(
        x=serie_anno["Anno"], y=serie_anno["NTN"],
        name="Compravendite (NTN)", opacity=0.45,
        marker_color=ACC2,
    ), secondary_y=True)
    for anno, sem, label in EVENTI:
        if sem == "S1":
            fig2.add_vline(x=anno, line_dash="dot",
                           line_color=ACC, line_width=1, opacity=0.4)
            fig2.add_annotation(x=anno, y=1, yref="paper", text=label,
                showarrow=False, font=dict(color=ACC2, size=10),
                textangle=-90, xshift=8)
    fig2.update_yaxes(title_text="Prezzo medio (€/mq)",
                      gridcolor="#2E4470", tickfont=dict(color=LGRAY),
                      secondary_y=False)
    fig2.update_yaxes(title_text="Compravendite (NTN)",
                      tickfont=dict(color=LGRAY), secondary_y=True)
    fig2.update_xaxes(gridcolor="#2E4470", tickfont=dict(color=LGRAY))
    fig2.update_layout(height=420, plot_bgcolor=BG2, paper_bgcolor=BG,
        font=dict(color=WHITE, family="Georgia"),
        legend=dict(bgcolor=BG2, bordercolor=ACC, borderwidth=1),
        margin=dict(l=50,r=60,t=30,b=50))
    st.plotly_chart(fig2, use_container_width=True)
    caption(
        "Le barre gialle mostrano quante case sono state comprate e vendute ogni anno "
        "(asse destro); la linea azzurra mostra il prezzo medio (asse sinistro). "
        "Nel 2021-2022 entrambe le misure crescono insieme: un momento irripetibile "
        "dovuto al Superbonus e ai tassi a zero. Dal 2023 le compravendite calano "
        "(-14%) ma i prezzi tengono: meno acquirenti, ma anche meno case disponibili."
    )


# =========================================================================
# SCHEDA 2 — DATI UTILIZZATI
# =========================================================================
with tab2:

    st.header("Dati utilizzati")
    st.markdown(
        "L'analisi si basa su tre fonti ufficiali italiane ed europee, "
        "tutte pubblicamente accessibili e gratuite."
    )

    # Disclaimer
    st.markdown(f"""
<div class="disclaimer-box">
<strong>Disclaimer</strong><br>
I dati contenuti in questa dashboard sono stati scaricati da fonti ufficiali pubbliche
e vengono utilizzati esclusivamente a fini accademici.
Non hanno alcuno scopo commerciale o di lucro.
</div>
""", unsafe_allow_html=True)

    st.write("")

    # Fonte 1: OMI
    st.markdown(f"**Fonte 1 — Agenzia delle Entrate, Osservatorio del Mercato Immobiliare (OMI)**")
    st.markdown(
        "Contiene le quotazioni immobiliari semestrali (prezzo minimo e massimo al metro quadro) "
        "e i volumi di compravendita per comune, fascia OMI e tipologia di immobile. "
        "Disponibile su: [agenziaentrate.gov.it](https://www.agenziaentrate.gov.it)"
    )
    with st.expander("Mostra i dati OMI"):
        omi_display = dati[[
            "Anno","Semestre","Prov","Citta","Comune_descrizione","Fascia",
            "Compr_min","Compr_max","Prezzo_medio_mq","NTN Totale"
        ]].rename(columns={
            "Citta":"Provincia","Comune_descrizione":"Comune",
            "Compr_min":"Prezzo min (€/mq)","Compr_max":"Prezzo max (€/mq)",
            "Prezzo_medio_mq":"Prezzo medio (€/mq)","NTN Totale":"Compravendite (NTN)",
        }).sort_values(["Anno","Semestre","Prov"]).reset_index(drop=True)
        st.dataframe(omi_display, use_container_width=True, height=400)
        st.caption(f"Totale righe: {len(omi_display):,} | Periodo: 2016-2025 | Province: BO, MI, NA, PA, RM, TO")

    st.write("")

    # Fonte 2: ISTAT
    st.markdown("**Fonte 2 — ISTAT, Indice dei Prezzi delle Abitazioni (IPAB)**")
    st.markdown(
        "Serie trimestrale che misura come cambiano nel tempo i prezzi delle abitazioni "
        "in Italia, con base 100 nell'anno 2025. Distingue tra abitazioni nuove e "
        "abitazioni esistenti. "
        "Disponibile su: [istat.it](https://www.istat.it)"
    )
    with st.expander("Mostra i dati ISTAT"):
        istat_display = df[[
            "Anno","Semestre","IPAB_tutte_voci",
            "IPAB_abitazioni_nuove","IPAB_abitazioni_esistenti"
        ]].drop_duplicates().sort_values(["Anno","Semestre"]).reset_index(drop=True)
        istat_display.columns = [
            "Anno","Semestre","IPAB tutte le abitazioni",
            "IPAB abitazioni nuove","IPAB abitazioni esistenti"
        ]
        st.dataframe(istat_display, use_container_width=True, height=300)
        st.caption("Totale righe: 20 (10 anni × 2 semestri) | Base: 2025 = 100")

    st.write("")

    # Fonte 3: BCE
    st.markdown("**Fonte 3 — Banca Centrale Europea (BCE), Tasso di rifinanziamento principale**")
    st.markdown(
        "Il tasso di interesse fissato dalla BCE, che influenza direttamente il costo "
        "dei mutui bancari e quindi la capacità delle famiglie di acquistare casa. "
        "La serie è stata convertita da variazioni puntuali a media semestrale. "
        "Disponibile su: [ecb.europa.eu](https://www.ecb.europa.eu)"
    )
    with st.expander("Mostra i dati BCE"):
        bce_display = df[[
            "Anno","Semestre","Tasso_BCE_medio_pct"
        ]].drop_duplicates().sort_values(["Anno","Semestre"]).reset_index(drop=True)
        bce_display.columns = ["Anno","Semestre","Tasso BCE medio semestrale (%)"]
        st.dataframe(bce_display, use_container_width=True, height=300)
        st.caption(
            "Totale righe: 20 | Nota: il tasso è rimasto a 0% dal 2016 al 2022, "
            "poi è salito rapidamente fino al 4.47% nel 2024, per poi scendere al 2.15% nel 2025."
        )


# =========================================================================
# SCHEDA 3 — DOVE E QUANTO
# =========================================================================
with tab3:

    # Mappa
    mappa_df = dati.groupby(["Prov","Citta"], as_index=False)["Prezzo_medio_mq"].mean()
    mappa_df["lat"] = mappa_df["Prov"].map(lambda p: COORDS[p][0])
    mappa_df["lon"] = mappa_df["Prov"].map(lambda p: COORDS[p][1])

    fig_mappa = px.scatter_mapbox(
        mappa_df, lat="lat", lon="lon",
        size="Prezzo_medio_mq", color="Prezzo_medio_mq",
        color_continuous_scale=["#00C2E0","#1E5799","#0B2545","#1B2A4A"],
        hover_name="Citta",
        hover_data={"Prezzo_medio_mq":":.0f","lat":False,"lon":False},
        zoom=4.8, center={"lat":42.5,"lon":12.5},
        mapbox_style="carto-positron", size_max=55,
        labels={"Prezzo_medio_mq":"Euro/mq"},
    )
    fig_mappa.update_coloraxes(colorbar=dict(
        tickfont=dict(color=WHITE),
        title=dict(text="Euro/mq", font=dict(color=WHITE))
    ))
    fig_mappa.update_layout(height=480, paper_bgcolor=BG,
                             margin=dict(l=0,r=0,t=0,b=0))
    st.plotly_chart(fig_mappa, use_container_width=True)
    caption(
        "Mappa delle 6 province analizzate. La dimensione e il colore di ogni punto "
        "rappresentano il prezzo medio al metro quadro nel periodo selezionato: "
        "più il punto è grande e chiaro, più il mercato è costoso."
    )

    st.write("")
    st.subheader("Heatmap: prezzo per città e per anno")

    heatmap_df = dati.groupby(["Citta","Anno"], as_index=False)["Prezzo_medio_mq"].mean()
    heatmap_pivot = heatmap_df.pivot(index="Citta", columns="Anno", values="Prezzo_medio_mq")
    heatmap_pivot = heatmap_pivot.loc[
        heatmap_pivot.mean(axis=1).sort_values(ascending=False).index
    ]
    fig3 = px.imshow(
        heatmap_pivot,
        color_continuous_scale=["#1B2A4A","#1E5799","#00C2E0","#FFFFFF"],
        labels=dict(x="Anno", y="", color="Euro/mq"),
        text_auto=".0f", aspect="auto",
    )
    fig3.update_traces(textfont=dict(color=BG, size=12))
    fig3 = layout_grafico(fig3, height=320)
    fig3.update_xaxes(side="bottom")
    fig3.update_coloraxes(colorbar=dict(
        tickfont=dict(color=WHITE), title=dict(font=dict(color=WHITE))
    ))
    st.plotly_chart(fig3, use_container_width=True)
    caption(
        "Ogni cella mostra il prezzo medio al metro quadro. Il colore va dal blu scuro "
        "(prezzi più bassi) al bianco (prezzi più alti). Si legge per riga (come cambia "
        "una città nel tempo) o per colonna (chi è più cara in un dato anno)."
    )

    st.write("")
    st.subheader("Posizione nel mercato: caro o economico, stabile o in crescita?")

    scatter_df = dati.groupby(["Prov","Citta","Anno"], as_index=False)["Prezzo_medio_mq"].mean()
    scatter_df = scatter_df.sort_values(["Prov","Anno"])
    scatter_df["Variazione_YoY"] = scatter_df.groupby("Prov")["Prezzo_medio_mq"].pct_change() * 100

    anno_scatter = st.select_slider(
        "Anno da analizzare",
        options=sorted(dati["Anno"].unique()),
        value=int(dati["Anno"].max()),
    )
    scatter_anno = scatter_df[
        (scatter_df["Anno"] == anno_scatter) &
        (scatter_df["Variazione_YoY"].notna())
    ]

    if len(scatter_anno) > 0:
        fig4 = px.scatter(
            scatter_anno, x="Prezzo_medio_mq", y="Variazione_YoY",
            color="Prov", color_discrete_map=COLORI,
            size=[40]*len(scatter_anno), text="Citta",
            labels={
                "Prezzo_medio_mq":"Prezzo medio (€/mq)",
                "Variazione_YoY":"Variazione % vs anno precedente",
            },
        )
        fig4.update_traces(textposition="top center",
                           textfont=dict(color=WHITE, size=12))
        x_mid = scatter_anno["Prezzo_medio_mq"].mean()
        y_vals = scatter_anno["Variazione_YoY"]
        y_max, y_min = y_vals.max(), y_vals.min()
        offset_y = (y_max - y_min) * 0.12 if (y_max - y_min) > 0 else 0.3

        fig4.add_hline(y=0, line_dash="dash", line_color=ACC, opacity=0.5)
        fig4.add_vline(x=x_mid, line_dash="dash", line_color=ACC, opacity=0.5)
        fig4.add_annotation(x=x_mid*0.88, y=y_max-offset_y,
            text="Economico e in crescita", showarrow=False,
            font=dict(color=ACC2, size=10), opacity=0.8)
        fig4.add_annotation(x=x_mid*1.12, y=y_max-offset_y,
            text="Caro e in crescita", showarrow=False,
            font=dict(color=ACC2, size=10), opacity=0.8)
        fig4.add_annotation(x=x_mid*0.88, y=y_min+offset_y,
            text="Economico e in calo", showarrow=False,
            font=dict(color=ACC2, size=10), opacity=0.8)
        fig4.add_annotation(x=x_mid*1.12, y=y_min+offset_y,
            text="Caro e in calo", showarrow=False,
            font=dict(color=ACC2, size=10), opacity=0.8)
        fig4 = layout_grafico(fig4, height=480)
        st.plotly_chart(fig4, use_container_width=True)
        caption(
            "Ogni punto è una provincia. L'asse orizzontale indica il prezzo medio "
            "(più a destra = più costosa), quello verticale la variazione rispetto "
            "all'anno precedente (sopra la linea = in crescita, sotto = in calo). "
            "Sposta lo slider in alto per vedere come le province si riposizionano anno dopo anno."
        )


# =========================================================================
# SCHEDA 4 — PREVISIONE 2026
# =========================================================================
with tab4:

    st.header("Previsione 2026")
    st.markdown(
        "Il modello è stato allenato su **20 semestri di dati storici** (2016-2025), "
        "usando il trend temporale, l'indice ISTAT dei prezzi e il tasso di interesse BCE. "
        "Sono stati confrontati due approcci statistici, scegliendo per ogni provincia "
        "quello che ha dato risultati migliori sui dati storici."
    )

    prev_filtrate    = prev[prev["Provincia"].isin(province_scelte)]
    sarimax_filtrate = sarimax[sarimax["Provincia"].isin(province_scelte)]

    # Gauge chart
    st.subheader("Prezzi previsti per il primo semestre 2026")

    n_prov = len(prev_filtrate)
    cols_gauge = st.columns(min(n_prov, 3))
    for i, (_, row) in enumerate(prev_filtrate.iterrows()):
        col = cols_gauge[i % 3]
        with col:
            prov            = row["Provincia"]
            prezzo_attuale  = row["Prezzo_H2_2025"]
            prezzo_previsto = row["Prezzo_previsto_H1_2026"]
            variazione      = row["Variazione_pct_prezzo"]
            gauge_min       = prezzo_attuale * 0.85
            gauge_max       = prezzo_attuale * 1.15

            fig_g = go.Figure(go.Indicator(
                mode="gauge+number+delta",
                value=prezzo_previsto,
                delta=dict(
                    reference=prezzo_attuale, valueformat=".0f", suffix=" €",
                    increasing=dict(color="#06D6A0"),
                    decreasing=dict(color="#EF476F"),
                ),
                number=dict(suffix=" €/mq", font=dict(color=WHITE, size=22)),
                gauge=dict(
                    axis=dict(range=[gauge_min, gauge_max],
                              tickfont=dict(color=LGRAY, size=9),
                              tickformat=".0f"),
                    bar=dict(color=COLORI.get(prov, ACC)),
                    bgcolor=BG2, bordercolor=ACC,
                    steps=[
                        dict(range=[gauge_min, prezzo_attuale], color="#1E3260"),
                        dict(range=[prezzo_attuale, gauge_max], color="#243655"),
                    ],
                    threshold=dict(line=dict(color=WHITE, width=2),
                                   thickness=0.8, value=prezzo_attuale),
                ),
                title=dict(
                    text=(f"<b>{NOMI[prov]}</b><br>"
                          f"<span style='font-size:12px;color:{ACC}'>"
                          f"{variazione:+.2f}% vs H2 2025</span>"),
                    font=dict(color=WHITE, size=15),
                ),
            ))
            fig_g.update_layout(height=280, paper_bgcolor=BG2,
                                 font=dict(color=WHITE),
                                 margin=dict(l=20,r=20,t=60,b=20))
            st.plotly_chart(fig_g, use_container_width=True)

    caption(
        "La lancetta indica il prezzo previsto per il primo semestre 2026. "
        "La linea bianca verticale è il valore attuale (H2 2025). "
        "Il delta mostra la variazione in euro rispetto all'ultimo semestre osservato."
    )

    st.write("")

    # Card per ogni provincia: modello scelto + motivazione
    st.subheader("Scelta dei modelli di previsione")

    province_ordinate = [p for p in ["BO","MI","NA","PA","RM","TO"]
                         if p in province_scelte]
    col_left, col_right = st.columns(2)

    for i, prov in enumerate(province_ordinate):
        mot = MOTIVAZIONI[prov]
        col = col_left if i % 2 == 0 else col_right

        with col:
            # Determiniamo etichette e previsioni per i due modelli
            if mot["modello"] == "SARIMAX":
                label_scelto = "SARIMAX"
                prev_scelto  = mot["previsione"]
                label_altro  = "Regressione"
                prev_altro   = mot["previsione_alt"]
            else:
                label_scelto = "Regressione"
                prev_scelto  = mot["previsione"]
                label_altro  = "SARIMAX"
                prev_altro   = mot["previsione_alt"]

            st.markdown(f"""
<div class="provincia-card">
<h3 style="color:{mot["colore"]};margin-top:0">{NOMI[prov]}</h3>

<table style="width:100%;border-collapse:collapse;margin:8px 0 12px 0">
  <tr>
    <th style="text-align:left;color:{LGRAY};font-size:12px;padding:4px 8px;
               border-bottom:1px solid #2E4470">Modello</th>
    <th style="text-align:right;color:{LGRAY};font-size:12px;padding:4px 8px;
               border-bottom:1px solid #2E4470">Previsione H1 2026</th>
    <th style="text-align:center;color:{LGRAY};font-size:12px;padding:4px 8px;
               border-bottom:1px solid #2E4470">Scelto</th>
  </tr>
  <tr style="background-color:#1E3260">
    <td style="padding:6px 8px;color:{ACC2};font-weight:700">{label_scelto}</td>
    <td style="text-align:right;padding:6px 8px;color:{WHITE};font-weight:700;font-size:16px">
      {prev_scelto:,.1f} €/mq ({mot["variazione"]:+.2f}%)
    </td>
    <td style="text-align:center;padding:6px 8px;font-size:16px">✓</td>
  </tr>
  <tr>
    <td style="padding:6px 8px;color:{LGRAY}">{label_altro}</td>
    <td style="text-align:right;padding:6px 8px;color:{LGRAY}">{prev_altro:,.1f} €/mq</td>
    <td style="text-align:center;padding:6px 8px;color:{LGRAY}">—</td>
  </tr>
</table>

<p style="margin:4px 0">
  <strong style="color:{ACC2}">Affidabilità:</strong>
  <span style="color:{LGRAY}"> {mot["affidabilita"]}</span>
</p>
<p style="margin:10px 0 0 0;color:{LGRAY};font-size:13px;font-style:italic">
  {mot["motivo"]}
</p>
</div>
""", unsafe_allow_html=True)

    st.write("")
    caption(
        "La Regressione polinomiale trova la curva matematica che meglio si adatta "
        "all'andamento storico dei prezzi. Funziona bene quando il mercato segue un "
        "percorso regolare e prevedibile. "
        "SARIMAX è un modello più sofisticato che impara il 'ritmo' della serie: "
        "tiene conto di quanto il prezzo di oggi dipende da quello dei semestri "
        "precedenti (autocorrelazione) e della stagionalità annuale. "
        "Vince nei mercati con trend recente forte e chiaro come Milano e Roma, "
        "ma rischia di andare in overfitting su serie piatte come Torino o Palermo."
    )


# =========================================================================
# PIE DI PAGINA
# =========================================================================
st.write("---")
st.caption(
    "Fonti: Agenzia delle Entrate (OMI) · ISTAT (Indice IPAB) · "
    "Banca Centrale Europea (tasso di rifinanziamento principale)"
)
