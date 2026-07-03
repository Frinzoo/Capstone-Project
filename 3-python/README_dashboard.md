# Dashboard interattiva - Mercato Immobiliare Italia

## Come avviarla (3 passaggi)

1. Apri il Terminale, vai nella cartella dove hai salvato questi 4 file:
   - `dashboard.py`
   - `dashboard_dataset.csv`
   - `dashboard_previsioni.csv`
   - `requirements_dashboard.txt`

2. Installa le librerie necessarie (basta farlo una volta sola):
   ```
   pip install -r requirements_dashboard.txt
   ```

3. Avvia la dashboard:
   ```
   streamlit run dashboard.py
   ```

Si apre automaticamente nel browser su `http://localhost:8501`. Per chiuderla,
torna al Terminale e premi `Ctrl+C`.

## Cosa puoi fare nella dashboard

- **Barra laterale** (sinistra): filtra per provincia, intervallo di anni, e scegli
  se vedere solo i comuni capoluogo o l'intera provincia. I filtri si applicano a
  tutte le schede.
- **Scheda Panoramica**: indicatori principali e prezzo medio per provincia.
- **Scheda Andamento prezzi**: grafico interattivo dell'evoluzione del prezzo nel
  tempo (annuale o semestrale).
- **Scheda Confronto province**: variazione percentuale anno su anno e classifica
  per qualsiasi anno selezionato.
- **Scheda Compravendite (NTN)**: andamento del volume di compravendite, con
  evidenziato il periodo di boom 2021-2022.
- **Scheda Previsione 2026**: le previsioni del modello per il primo semestre 2026,
  a confronto con l'ultimo dato osservato.

## Note

- I dati sono caricati dai due file CSV nella stessa cartella: se vuoi aggiornare
  i dati, basta sostituire quei file (mantenendo lo stesso nome e formato colonne)
  e riavviare la dashboard.
- Attenzione alla provincia di Napoli (sigla "NA"): il codice gestisce già
  correttamente il fatto che "NA" potrebbe essere confuso con un valore mancante
  da pandas, ma se modifichi i CSV a mano ricordatene.
