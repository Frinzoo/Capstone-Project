-- ======================================================================--
-- COSA TROVI IN QUESTO FILE (in ordine):
--
--   PARTE 1 - Creazione del database e delle tabelle
--   PARTE 2 - Importazione dei dati dai file CSV
--   PARTE 3 - Controlli di qualità
--   PARTE 4 - Calcolo del prezzo medio delle case, per provincia e per città
--   PARTE 5 - Variazioni prezzi
--   PARTE 6 - Classifica delle province/città più costose, anno per anno
--   PARTE 7 - Query salvate che si possono riutilizzare comodamente
--   PARTE 8 - Modello di previsione del prezzo per il 2026
--
-- Questo file è pensato per essere letto ed eseguito dall'inizio alla fine,
-- un blocco alla volta. Ogni blocco è preceduto da un commento che spiega,
-- in parole semplici, cosa fa e perché.
--
-- DATI DI PARTENZA: quotazioni immobiliari (OMI) e volumi di compravendita
-- (VCN) dell'Agenzia delle Entrate, periodo 2016-2025, sei province italiane
-- (Bologna, Milano, Napoli, Palermo, Roma, Torino), integrati con l'indice
-- dei prezzi delle case ISTAT e il tasso di interesse di riferimento BCE.
-- ======================================================================


-- ======================================================================
-- PARTE 1 - CREAZIONE DEL DATABASE E DELLE TABELLE
-- ======================================================================

-- Per prima cosa creiamo un "contenitore" per tutti i nostri dati: il
-- database. Se esiste già non succede niente di male (grazie a "IF NOT
-- EXISTS" non otteniamo un errore se lo eseguiamo più volte per sbaglio).
-- La parte "CHARACTER SET utf8mb4" serve per essere sicuri che il database
-- gestisca correttamente le lettere accentate italiane (è, à, ò...).
CREATE DATABASE IF NOT EXISTS Database_immobiliare
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Da qui in avanti, diciamo a MySQL che vogliamo lavorare dentro questo
-- database specifico (un po' come aprire una cartella prima di mettere
-- dentro dei file).
USE Database_immobiliare;

-- Adesso creiamo la tabella principale, quella con tutti i dati immobiliari.
-- Ogni riga di questa tabella rappresenta: un certo tipo di casa, in una
-- certa zona di un comune, in un certo semestre. Ad esempio: "le abitazioni
-- civili in stato normale, zona B di Bologna, nel primo semestre 2020".
--
-- Per ogni colonna abbiamo scelto un "tipo di dato" adatto:
--   - VARCHAR(n)  = testo, con un numero massimo di caratteri
--   - SMALLINT    = numero intero piccolo (va benissimo per un anno, es. 2020)
--   - INT         = numero intero (per i prezzi in euro, che sono cifre tonde)
--   - DECIMAL(a,b)= numero con la virgola, dove "a" è il numero totale di
--                   cifre e "b" quante sono dopo la virgola (es. DECIMAL(10,2)
--                   vuol dire fino a 10 cifre, di cui 2 dopo la virgola)
CREATE TABLE omi_qi_vcn (
    id                  INT AUTO_INCREMENT PRIMARY KEY,  -- numero identificativo automatico di ogni riga
    Semestre            VARCHAR(2)      NOT NULL,        -- 'S1' (gennaio-giugno) o 'S2' (luglio-dicembre)
    Anno                SMALLINT        NOT NULL,        -- l'anno, es. 2020
    Prov                VARCHAR(2)      NOT NULL,        -- sigla provincia: BO, MI, NA, PA, RM, TO
    Comune_amm          VARCHAR(10)     NOT NULL,        -- codice del comune secondo l'OMI
    Comune_descrizione  VARCHAR(100)    NOT NULL,        -- nome del comune scritto per esteso
    Fascia              VARCHAR(2)      NOT NULL,        -- zona della città secondo l'OMI (B, C, D, E, R)
    Descr_Tipologia     VARCHAR(50)     NOT NULL,        -- tipo di immobile, es. 'Abitazioni civili'
    Stato               VARCHAR(20)     NOT NULL,        -- stato di conservazione, es. 'NORMALE'
    Compr_min           INT             NOT NULL,        -- prezzo minimo al metro quadro (euro)
    Compr_max           INT             NOT NULL,        -- prezzo massimo al metro quadro (euro)
    NTN_Totale          DECIMAL(10,2)   NOT NULL,        -- numero di compravendite "normalizzate" in un anno
    Prezzo_medio_mq      DECIMAL(10,2)   NOT NULL,        -- calcolato come (prezzo minimo + prezzo massimo) / 2
    -- I tre "INDEX" seguenti non aggiungono nuove informazioni, ma servono
    -- a velocizzare le ricerche quando filtriamo per provincia+anno, per
    -- comune o per anno+semestre, che sono le ricerche più frequenti.
    INDEX idx_prov_anno (Prov, Anno),
    INDEX idx_comune (Comune_amm),
    INDEX idx_anno_semestre (Anno, Semestre)
) ENGINE=InnoDB;

-- Creiamo ora una seconda tabella, separata dalla prima, che contiene solo
-- i tassi di interesse della Banca Centrale Europea (BCE). L'abbiamo tenuta
-- separata perché il tasso BCE non dipende dal comune o dalla provincia,
-- ma solo dal periodo di tempo: avrebbe poco senso ripetere lo stesso
-- numero su migliaia di righe della tabella principale.
--
-- "PRIMARY KEY (Anno, Semestre)" significa che la combinazione di Anno e
-- Semestre deve essere unica: non possono esistere due righe con lo stesso
-- anno e semestre.
CREATE TABLE bce_tassi (
    Anno                 SMALLINT      NOT NULL,
    Semestre              VARCHAR(2)    NOT NULL,
    Tasso_BCE_medio_pct   DECIMAL(6,3)  NOT NULL,  -- tasso di rifinanziamento principale, in percentuale
    PRIMARY KEY (Anno, Semestre)
) ENGINE=InnoDB;

-- Stessa logica per l'indice ISTAT dei prezzi delle abitazioni: anche
-- questo è un dato "macroeconomico", legato solo al tempo e non al comune.
CREATE TABLE istat_ipab (
    Anno                        SMALLINT      NOT NULL,
    Semestre                     VARCHAR(2)    NOT NULL,
    IPAB_tutte_voci              DECIMAL(6,2)  NOT NULL,  -- indice generale prezzi abitazioni (base 2025=100)
    IPAB_abitazioni_nuove        DECIMAL(6,2)  NOT NULL,  -- stesso indice, solo case nuove
    IPAB_abitazioni_esistenti    DECIMAL(6,2)  NOT NULL,  -- stesso indice, solo case già esistenti
    PRIMARY KEY (Anno, Semestre)
) ENGINE=InnoDB;


-- ======================================================================
-- PARTE 2 - IMPORTAZIONE DEI DATI DAI FILE CSV
-- ======================================================================

-- Le tabelle che abbiamo appena creato sono vuote: dobbiamo riempirle con
-- i dati veri, che abbiamo preparato ed esportato in tre file CSV.
--
-- IMPORTANTE: il comando "LOAD DATA LOCAL INFILE" richiede che sul tuo
-- MySQL sia attivata l'opzione "local_infile" (a volte disattivata di
-- default per motivi di sicurezza). Se ottieni un errore, prova a eseguire
-- prima: SET GLOBAL local_infile = 1;
--
-- Devi anche modificare il percorso del file ('/percorso/locale/...') con
-- la posizione reale dei file CSV sul tuo computer.

-- Importiamo i dati immobiliari nella tabella principale.
-- "FIELDS TERMINATED BY ';'" dice a MySQL che le colonne nel file sono
-- separate dal punto e virgola (non dalla virgola, come spesso si pensa).
-- "IGNORE 1 ROWS" salta la prima riga del file, quella con i nomi delle
-- colonne (l'intestazione), che non va caricata come se fosse un dato.
LOAD DATA LOCAL INFILE '/Users/francescolagana/Desktop/Capstone Project EPICODE/data/processed'
INTO TABLE omi_qi_vcn
FIELDS TERMINATED BY ';' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Semestre, Anno, Prov, Comune_amm, Comune_descrizione, Fascia,
 Descr_Tipologia, Stato, Compr_min, Compr_max, NTN_Totale, Prezzo_medio_mq);

-- Stessa cosa per i tassi BCE
LOAD DATA LOCAL INFILE '/percorso/locale/bce_tassi.csv'
INTO TABLE bce_tassi
FIELDS TERMINATED BY ';' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Anno, Semestre, Tasso_BCE_medio_pct);

-- E per l'indice ISTAT
LOAD DATA LOCAL INFILE '/percorso/locale/istat_ipab.csv'
INTO TABLE istat_ipab
FIELDS TERMINATED BY ';' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Anno, Semestre, IPAB_tutte_voci, IPAB_abitazioni_nuove, IPAB_abitazioni_esistenti);


-- ======================================================================
-- PARTE 3 - CONTROLLI DI QUALITA' DEI DATI
-- ======================================================================

-- Prima di iniziare ad analizzare i dati, è buona abitudine controllare
-- che tutto sia andato bene con l'importazione. Facciamo quattro verifiche.

-- 3.1) Contiamo quante righe ci sono in ciascuna tabella. Ci aspettiamo
-- circa 41.864 righe nella tabella principale, e 20 righe in ciascuna
-- delle due tabelle macroeconomiche (10 anni x 2 semestri).
SELECT 'omi_qi_vcn' AS Tabella, COUNT(*) AS Numero_Righe FROM omi_qi_vcn
UNION ALL
SELECT 'bce_tassi', COUNT(*) FROM bce_tassi
UNION ALL
SELECT 'istat_ipab', COUNT(*) FROM istat_ipab;

-- 3.2) Controlliamo come sono fatte le colonne delle nostre tabelle
-- (che tipo di dato contengono, se possono essere vuote, eccetera).
-- "DESCRIBE" è un comando che mostra la struttura di una tabella.
DESCRIBE omi_qi_vcn;
DESCRIBE bce_tassi;
DESCRIBE istat_ipab;

-- 3.3) Controlliamo che non ci siano valori "vuoti" (NULL) nelle colonne
-- più importanti. Se questa query restituisce tutti zeri nelle colonne
-- "null_...", vuol dire che i dati sono completi e puliti.
SELECT
  COUNT(*)                                            AS Totale_Righe,
  SUM(CASE WHEN Prov IS NULL THEN 1 ELSE 0 END)        AS Valori_Vuoti_Provincia,
  SUM(CASE WHEN NTN_Totale IS NULL THEN 1 ELSE 0 END)  AS Valori_Vuoti_NTN,
  SUM(CASE WHEN Compr_min IS NULL THEN 1 ELSE 0 END)   AS Valori_Vuoti_Prezzo_Min,
  SUM(CASE WHEN Compr_max IS NULL THEN 1 ELSE 0 END)   AS Valori_Vuoti_Prezzo_Max
FROM omi_qi_vcn;

-- 3.4) Controlliamo quali sigle di provincia sono effettivamente presenti
-- nei dati. Ci aspettiamo di vedere esattamente sei righe: BO, MI, NA, PA,
-- RM, TO. Se ne comparisse una diversa, vorrebbe dire che c'è un errore
-- nei dati di partenza.
SELECT DISTINCT Prov FROM omi_qi_vcn ORDER BY Prov;


-- ======================================================================
-- PARTE 4 - PREZZO MEDIO DELLE CASE, DAL 2016 AL 2025
-- ======================================================================

-- Qui iniziamo la parte più interessante: capire quanto costano le case
-- e come è cambiato il prezzo nel tempo.

-- 4.1) Prezzo medio per PROVINCIA (cioè considerando tutti i comuni della
-- provincia, non solo il capoluogo), anno per anno. "GROUP BY" raggruppa
-- le righe che hanno la stessa provincia e lo stesso anno, e "AVG()"
-- calcola la media dei prezzi all'interno di ogni gruppo.
SELECT
  Prov                            AS Provincia,
  Anno,
  ROUND(AVG(Prezzo_medio_mq), 0)  AS Prezzo_Medio_Annuo_EuroMq
FROM omi_qi_vcn
GROUP BY Prov, Anno
ORDER BY Prov, Anno;

-- 4.2) Stessa cosa, ma guardando solo i sei comuni capoluogo (Bologna,
-- Milano, Napoli, Palermo, Roma, Torino città, non l'intera provincia).
-- Il prezzo qui sarà più alto rispetto alla media provinciale, perché il
-- capoluogo è quasi sempre la zona più cara della provincia.
SELECT
  Comune_descrizione              AS Citta,
  Anno,
  ROUND(AVG(Prezzo_medio_mq), 0)  AS Prezzo_Medio_Annuo_EuroMq
FROM omi_qi_vcn
WHERE Comune_descrizione IN ('BOLOGNA','MILANO','NAPOLI','PALERMO','ROMA','TORINO')
GROUP BY Comune_descrizione, Anno
ORDER BY Comune_descrizione, Anno;


-- ======================================================================
-- PARTE 5 - QUANTO SONO SALITI O SCESI I PREZZI (VARIAZIONE PERCENTUALE)
-- ======================================================================

-- Sapere il prezzo medio anno per anno è utile, ma è ancora più
-- interessante sapere DI QUANTO è cambiato rispetto all'anno precedente.
-- Per farlo usiamo una funzione speciale di SQL chiamata "finestra"
-- (window function): LAG().
--
-- LAG() ci permette di "guardare indietro" e prendere il valore della
-- riga precedente (nel nostro caso, il prezzo dell'anno prima), pur
-- restando sulla riga corrente. È come avere due colonne affiancate:
-- il prezzo di quest'anno e il prezzo dell'anno scorso, pronte per essere
-- confrontate.

-- 5.1) Variazione percentuale anno su anno, per PROVINCIA.
-- "WITH ... AS (...)" crea una tabella temporanea, valida solo per la
-- query che segue: qui calcoliamo prima il prezzo medio per ogni
-- provincia e anno, e poi nella query principale usiamo LAG() su questo
-- risultato.
WITH prezzo_annuo_provincia AS (
  SELECT
    Prov,
    Anno,
    ROUND(AVG(Prezzo_medio_mq), 0) AS Prezzo_medio_annuo
  FROM omi_qi_vcn
  GROUP BY Prov, Anno
)
SELECT
  Prov                                AS Provincia,
  Anno,
  Prezzo_medio_annuo                  AS Prezzo_Di_Questo_Anno,
  -- "PARTITION BY Prov" dice a LAG() di guardare indietro solo all'interno
  -- della stessa provincia: non vogliamo confrontare per sbaglio il prezzo
  -- di Roma 2020 con quello di Bologna 2019.
  LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno) AS Prezzo_Anno_Precedente,
  -- La variazione percentuale si calcola con la formula classica:
  -- (valore nuovo - valore vecchio) / valore vecchio, moltiplicato per 100
  ROUND(
    (Prezzo_medio_annuo - LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno))
    * 100.0 / LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno), 2
  ) AS Variazione_Percentuale
FROM prezzo_annuo_provincia
ORDER BY Prov, Anno;
-- NOTA: per il primo anno di ogni provincia (il 2016), la colonna
-- "Prezzo_Anno_Precedente" sarà vuota (NULL), perché non esiste un anno
-- prima nei nostri dati. Questo è normale e atteso, non un errore.

-- 5.2) Stessa identica logica, ma per i sei comuni capoluogo.
WITH prezzo_annuo_citta AS (
  SELECT
    Comune_descrizione,
    Anno,
    ROUND(AVG(Prezzo_medio_mq), 0) AS Prezzo_medio_annuo
  FROM omi_qi_vcn
  WHERE Comune_descrizione IN ('BOLOGNA','MILANO','NAPOLI','PALERMO','ROMA','TORINO')
  GROUP BY Comune_descrizione, Anno
)
SELECT
  Comune_descrizione                  AS Citta,
  Anno,
  Prezzo_medio_annuo                  AS Prezzo_Di_Questo_Anno,
  LAG(Prezzo_medio_annuo) OVER (PARTITION BY Comune_descrizione ORDER BY Anno) AS Prezzo_Anno_Precedente,
  ROUND(
    (Prezzo_medio_annuo - LAG(Prezzo_medio_annuo) OVER (PARTITION BY Comune_descrizione ORDER BY Anno))
    * 100.0 / LAG(Prezzo_medio_annuo) OVER (PARTITION BY Comune_descrizione ORDER BY Anno), 2
  ) AS Variazione_Percentuale
FROM prezzo_annuo_citta
ORDER BY Comune_descrizione, Anno;


-- ======================================================================
-- PARTE 6 - CLASSIFICA DELLE PROVINCE/CITTA' PIU' COSTOSE
-- ======================================================================

-- Un'altra domanda interessante è: ogni anno, quali sono le province (o
-- città) più care? Per rispondere usiamo un'altra "finestra", RANK(),
-- che assegna una posizione in classifica (1, 2, 3, ...) a ogni riga,
-- in base a un ordinamento che scegliamo noi.

-- 6.1) Classifica delle PROVINCE per prezzo medio, anno per anno.
-- "PARTITION BY Anno" vuol dire: ricomincia la classifica da capo per
-- ogni anno (altrimenti otterremmo un'unica classifica su tutti gli anni
-- insieme, che non avrebbe senso). "ORDER BY Prezzo_medio_annuo DESC"
-- vuol dire: la provincia più cara prende la posizione numero 1.
WITH prezzo_annuo_provincia AS (
  SELECT
    Prov,
    Anno,
    ROUND(AVG(Prezzo_medio_mq), 0) AS Prezzo_medio_annuo
  FROM omi_qi_vcn
  GROUP BY Prov, Anno
)
SELECT
  Prov                AS Provincia,
  Anno,
  Prezzo_medio_annuo  AS Prezzo_Medio,
  RANK() OVER (PARTITION BY Anno ORDER BY Prezzo_medio_annuo DESC) AS Posizione_In_Classifica
FROM prezzo_annuo_provincia
ORDER BY Anno, Posizione_In_Classifica;

-- 6.2) Stessa classifica, ma per i sei comuni capoluogo. Un risultato
-- interessante che si scopre con questa query: a livello di provincia
-- Roma è sempre la più cara, ma guardando solo il comune capoluogo,
-- a partire dal 2025 Milano supera Roma in cima alla classifica.
WITH prezzo_annuo_citta AS (
  SELECT
    Comune_descrizione,
    Anno,
    ROUND(AVG(Prezzo_medio_mq), 0) AS Prezzo_medio_annuo
  FROM omi_qi_vcn
  WHERE Comune_descrizione IN ('BOLOGNA','MILANO','NAPOLI','PALERMO','ROMA','TORINO')
  GROUP BY Comune_descrizione, Anno
)
SELECT
  Comune_descrizione  AS Citta,
  Anno,
  Prezzo_medio_annuo  AS Prezzo_Medio,
  RANK() OVER (PARTITION BY Anno ORDER BY Prezzo_medio_annuo DESC) AS Posizione_In_Classifica
FROM prezzo_annuo_citta
ORDER BY Anno, Posizione_In_Classifica;


-- ======================================================================
-- PARTE 7 - VISTE: QUERY "SALVATE" DA RIUTILIZZARE FACILMENTE
-- ======================================================================

-- Finora abbiamo scritto query che, una volta eseguite, restituiscono un
-- risultato e basta. Una "vista" (VIEW) è invece una query che salviamo
-- con un nome, come se fosse una tabella: possiamo interrogarla in
-- qualsiasi momento con un semplice "SELECT * FROM nome_vista", senza
-- dover riscrivere tutto il codice ogni volta. È molto comodo quando una
-- stessa analisi serve spesso, ad esempio per costruire un report o una
-- dashboard.

-- 7.1) Vista con il prezzo medio ANNUALE per ogni provincia, già pronta.
-- "CREATE OR REPLACE VIEW" crea la vista, e se esiste già la sostituisce
-- (utile se dobbiamo correggere qualcosa senza prima doverla cancellare).
CREATE OR REPLACE VIEW vw_prezzo_annuale_provincia AS
SELECT
  Prov                            AS Provincia,
  Anno,
  COUNT(*)                        AS Numero_Osservazioni,
  ROUND(AVG(Prezzo_medio_mq), 0)  AS Prezzo_Medio_Annuo,
  ROUND(AVG(NTN_Totale), 0)       AS Compravendite_Medie
FROM omi_qi_vcn
GROUP BY Prov, Anno;

-- 7.2) Stessa cosa ma con il dettaglio SEMESTRALE (più preciso, utile per
-- analisi più fini o per il modello di previsione che vedremo più avanti).
CREATE OR REPLACE VIEW vw_prezzo_semestrale_provincia AS
SELECT
  Prov                                AS Provincia,
  Anno,
  Semestre,
  COUNT(*)                            AS Numero_Osservazioni,
  ROUND(AVG(Prezzo_medio_mq), 0)      AS Prezzo_Medio_Semestrale,
  ROUND(AVG(NTN_Totale), 0)           AS Compravendite_Medie
FROM omi_qi_vcn
GROUP BY Prov, Anno, Semestre;

-- 7.3) Vista con il dettaglio dei prezzi minimi e massimi osservati,
-- sempre a livello di provincia e semestre. Utile per capire non solo il
-- prezzo medio, ma anche quanto è ampio il divario tra zone più economiche
-- e zone più costose della stessa provincia.
CREATE OR REPLACE VIEW vw_prezzi_dettaglio_provincia AS
SELECT
  Prov                            AS Provincia,
  Anno,
  Semestre,
  COUNT(*)                        AS Numero_Osservazioni,
  ROUND(AVG(Prezzo_medio_mq), 1)  AS Prezzo_Medio,
  ROUND(MIN(Compr_min), 0)        AS Prezzo_Minimo_Osservato,
  ROUND(MAX(Compr_max), 0)        AS Prezzo_Massimo_Osservato
FROM omi_qi_vcn
GROUP BY Prov, Anno, Semestre;

-- 7.4) Vista con la variazione percentuale già calcolata e pronta
-- all'uso (la stessa logica della PARTE 5, ma salvata come vista).
CREATE OR REPLACE VIEW vw_prezzo_variazione_percentuale AS
WITH prezzo_annuo AS (
  SELECT
    Prov,
    Anno,
    ROUND(AVG(Prezzo_medio_mq), 1) AS Prezzo_medio_annuo
  FROM omi_qi_vcn
  GROUP BY Prov, Anno
)
SELECT
  Prov                AS Provincia,
  Anno,
  Prezzo_medio_annuo  AS Prezzo_Medio,
  LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno) AS Prezzo_Anno_Precedente,
  ROUND(
    (Prezzo_medio_annuo - LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno))
    * 100.0 / LAG(Prezzo_medio_annuo) OVER (PARTITION BY Prov ORDER BY Anno), 2
  ) AS Variazione_Percentuale
FROM prezzo_annuo;

-- 7.5) Infine, una vista che "unisce" (JOIN) i dati immobiliari con le
-- due tabelle macroeconomiche (BCE e ISTAT). "LEFT JOIN" significa che
-- manteniamo tutte le righe della prima tabella anche se, per qualche
-- semestre, non trovassimo un dato BCE o ISTAT corrispondente (in questo
-- caso non capita mai, ma è una precauzione prudente). Questa vista è il
-- punto di partenza più comodo per costruire un modello di previsione,
-- perché ha già tutto quello che serve in un'unica tabella.
CREATE OR REPLACE VIEW vw_prezzo_con_dati_macro AS
SELECT
  v.Provincia,
  v.Anno,
  v.Semestre,
  v.Prezzo_Medio_Semestrale,
  v.Compravendite_Medie,
  b.Tasso_BCE_medio_pct  AS Tasso_BCE,
  i.IPAB_tutte_voci      AS Indice_ISTAT_Generale,
  i.IPAB_abitazioni_esistenti AS Indice_ISTAT_Case_Esistenti
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre;

-- Un paio di esempi di come si usano queste viste, una volta create:
SELECT * FROM vw_prezzo_annuale_provincia WHERE Provincia = 'RM' ORDER BY Anno;
SELECT * FROM vw_prezzo_con_dati_macro WHERE Provincia = 'MI' ORDER BY Anno, Semestre;


-- ======================================================================
-- PARTE 8 - MODELLO DI PREVISIONE DEL PREZZO PER IL 2026 (IN PURO SQL)
-- ======================================================================

-- Questa è la parte più avanzata dello script. L'obiettivo è prevedere
-- quale sarà il prezzo medio delle case nel primo semestre del 2026,
-- usando solo query SQL (senza bisogno di Python o altri programmi).
--
-- L'idea, spiegata semplice: guardiamo come si è mosso il prezzo negli
-- ultimi 10 anni (20 semestri, dal 2016 al 2025) e proviamo a "tirare
-- una riga" che segua il più possibile l'andamento osservato, tenendo
-- conto anche di due fattori che influenzano il mercato immobiliare:
-- l'indice ISTAT dei prezzi delle case e il tasso di interesse della BCE
-- (quando i mutui costano di più, in genere le persone comprano meno case
-- o sono disposte a pagarle meno).
--
-- Lo stesso identico procedimento viene ripetuto per ciascuna delle sei
-- province, una dopo l'altra qui sotto.
--
-- NOTA METODOLOGICA IMPORTANTE: per calcolare la previsione abbiamo
-- usato sempre TUTTI i 20 semestri disponibili (dal 2016 al 2025), senza
-- escluderne nessuno, per non alterare il risultato finale e mantenere
-- l'analisi più aderente possibile alla realtà dei dati.
--
-- I valori di indice ISTAT e tasso BCE per il primo semestre 2026 (che
-- ovviamente non sono ancora stati pubblicati, visto che il semestre non
-- è nemmeno concluso) sono stati stimati: l'indice ISTAT è stato
-- prolungato seguendo l'andamento degli ultimi 4 semestri noti, mentre
-- per il tasso BCE è stato usato l'ultimo valore ufficiale disponibile.

-- ----------------------------------------------------------------
-- Provincia: Bologna (sigla "BO")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_bo AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'BO';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_bo
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'BO' AS Provincia,
  'Bologna' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ----------------------------------------------------------------
-- Provincia: Milano (sigla "MI")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_mi AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'MI';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_mi
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'MI' AS Provincia,
  'Milano' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ----------------------------------------------------------------
-- Provincia: Napoli (sigla "NA")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_na AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'NA';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_na
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'NA' AS Provincia,
  'Napoli' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ----------------------------------------------------------------
-- Provincia: Palermo (sigla "PA")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_pa AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'PA';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_pa
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'PA' AS Provincia,
  'Palermo' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ----------------------------------------------------------------
-- Provincia: Roma (sigla "RM")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_rm AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'RM';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_rm
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'RM' AS Provincia,
  'Roma' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ----------------------------------------------------------------
-- Provincia: Torino (sigla "TO")
-- ----------------------------------------------------------------

-- Per prima cosa creiamo una "vista di appoggio" solo per questa provincia:
-- prendiamo i dati semestrali, ci agganciamo ai tassi BCE e all'indice ISTAT
-- dello stesso semestre, e creiamo un numero progressivo "t" che rappresenta
-- il tempo che passa (1 = primo semestre 2016, 2 = secondo semestre 2016, ...
-- fino a 20 = secondo semestre 2025). Questo numero "t" è quello che il
-- modello userà per capire l'andamento nel tempo.
CREATE OR REPLACE VIEW vw_serie_modello_to AS
SELECT
  v.Prov,
  v.Anno,
  v.Semestre,
  v.Prezzo_medio_semestrale AS Prezzo_medio_mq,
  v.NTN_medio_comune,
  i.IPAB_tutte_voci,
  b.Tasso_BCE_medio_pct,
  -- Calcolo del numero progressivo del semestre (t)
  (v.Anno - 2016) * 2 + (CASE WHEN v.Semestre = 'S1' THEN 1 ELSE 2 END) AS t
FROM vw_prezzo_semestrale_provincia v
LEFT JOIN bce_tassi  b ON v.Anno = b.Anno AND v.Semestre = b.Semestre
LEFT JOIN istat_ipab i ON v.Anno = i.Anno AND v.Semestre = i.Semestre
WHERE v.Prov = 'TO';

-- Ora calcoliamo il modello vero e proprio. L'idea di fondo è semplice:
-- vogliamo trovare una formula del tipo
--     Prezzo = a + (b1 * tempo) + (b2 * indice ISTAT) + (b3 * tasso BCE)
-- che si avvicini il più possibile ai prezzi osservati negli ultimi 10 anni.
-- Questo si chiama "regressione lineare multipla" ed è un classico strumento
-- di statistica per capire come più fattori insieme influenzano un risultato.
--
-- Il modo in cui SQL calcola i numeri "a", "b1", "b2", "b3" si chiama
-- "metodo dei minimi quadrati": in pratica si cercano i valori che rendono
-- più piccola possibile la differenza tra i prezzi previsti dalla formula
-- e i prezzi realmente osservati. Per trovarli servono solo delle somme
-- (SUM) calcolate sui dati, niente di più complicato.
WITH statistiche_di_base AS (
  -- Qui calcoliamo tutte le somme che ci servono: quante osservazioni
  -- abbiamo, la somma di ogni variabile, e la somma dei prodotti incrociati
  -- tra le variabili (es. tempo moltiplicato per prezzo, ISTAT moltiplicato
  -- per BCE, eccetera). Sono gli "ingredienti" della formula matematica.
  SELECT
    COUNT(*)                                       AS n,
    SUM(t)                                          AS sum_t,
    SUM(IPAB_tutte_voci)                            AS sum_ipab,
    SUM(Tasso_BCE_medio_pct)                        AS sum_bce,
    SUM(Prezzo_medio_mq)                            AS sum_y,
    SUM(t*t)                                        AS sum_tt,
    SUM(t*IPAB_tutte_voci)                          AS sum_t_ipab,
    SUM(t*Tasso_BCE_medio_pct)                      AS sum_t_bce,
    SUM(t*Prezzo_medio_mq)                          AS sum_t_y,
    SUM(IPAB_tutte_voci*IPAB_tutte_voci)            AS sum_ipab2,
    SUM(IPAB_tutte_voci*Tasso_BCE_medio_pct)        AS sum_ipab_bce,
    SUM(IPAB_tutte_voci*Prezzo_medio_mq)            AS sum_ipab_y,
    SUM(Tasso_BCE_medio_pct*Tasso_BCE_medio_pct)    AS sum_bce2,
    SUM(Tasso_BCE_medio_pct*Prezzo_medio_mq)        AS sum_bce_y
  FROM vw_serie_modello_to
),
-- Questo passaggio è il più "tecnico" e si può tranquillamente non capire
-- nel dettaglio: si tratta di risolvere un sistema di equazioni con il
-- metodo dei determinanti (regola di Cramer), un procedimento di algebra
-- che si studia alle superiori. Il risultato finale (più sotto) sono
-- comunque solo 4 numeri: l'intercetta e i 3 coefficienti della formula.
determinanti AS (
  SELECT
    (-sum_bce*sum_bce*sum_ipab2*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce + sum_bce*sum_ipab*sum_ipab_bce*sum_tt - sum_bce*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce*sum_ipab2*sum_t*sum_t_bce - sum_bce2*sum_ipab*sum_ipab*sum_tt + sum_bce2*sum_ipab*sum_t*sum_t_ipab + sum_bce2*sum_ipab*sum_t*sum_t_ipab - sum_bce2*sum_ipab2*sum_t*sum_t + sum_bce2*sum_ipab2*sum_tt*n - sum_bce2*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t - sum_ipab_bce*sum_ipab_bce*sum_tt*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n + sum_ipab_bce*sum_t_bce*sum_t_ipab*n - sum_ipab2*sum_t_bce*sum_t_bce*n) AS det_main,
    (-sum_bce*sum_bce_y*sum_ipab2*sum_tt + sum_bce*sum_bce_y*sum_t_ipab*sum_t_ipab + sum_bce*sum_ipab_bce*sum_ipab_y*sum_tt - sum_bce*sum_ipab_bce*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t_bce*sum_t_y - sum_bce*sum_ipab_y*sum_t_bce*sum_t_ipab - sum_bce2*sum_ipab*sum_ipab_y*sum_tt + sum_bce2*sum_ipab*sum_t_ipab*sum_t_y - sum_bce2*sum_ipab2*sum_t*sum_t_y + sum_bce2*sum_ipab2*sum_tt*sum_y + sum_bce2*sum_ipab_y*sum_t*sum_t_ipab - sum_bce2*sum_t_ipab*sum_t_ipab*sum_y + sum_bce_y*sum_ipab*sum_ipab_bce*sum_tt - sum_bce_y*sum_ipab*sum_t_bce*sum_t_ipab - sum_bce_y*sum_ipab_bce*sum_t*sum_t_ipab + sum_bce_y*sum_ipab2*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t_bce*sum_t_y + sum_ipab*sum_ipab_y*sum_t_bce*sum_t_bce + sum_ipab_bce*sum_ipab_bce*sum_t*sum_t_y - sum_ipab_bce*sum_ipab_bce*sum_tt*sum_y + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab_bce*sum_ipab_y*sum_t*sum_t_bce + sum_ipab_bce*sum_t_bce*sum_t_ipab*sum_y - sum_ipab2*sum_t_bce*sum_t_bce*sum_y) AS det_a,
    (-sum_bce*sum_bce*sum_ipab2*sum_t_y + sum_bce*sum_bce*sum_ipab_y*sum_t_ipab - sum_bce*sum_bce_y*sum_ipab*sum_t_ipab + sum_bce*sum_bce_y*sum_ipab2*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab_bce*sum_ipab_y*sum_t + sum_bce*sum_ipab*sum_ipab_bce*sum_t_y - sum_bce*sum_ipab*sum_ipab_y*sum_t_bce - sum_bce*sum_ipab_bce*sum_t_ipab*sum_y + sum_bce*sum_ipab2*sum_t_bce*sum_y - sum_bce2*sum_ipab*sum_ipab*sum_t_y + sum_bce2*sum_ipab*sum_ipab_y*sum_t + sum_bce2*sum_ipab*sum_t_ipab*sum_y - sum_bce2*sum_ipab2*sum_t*sum_y + sum_bce2*sum_ipab2*sum_t_y*n - sum_bce2*sum_ipab_y*sum_t_ipab*n + sum_bce_y*sum_ipab*sum_ipab*sum_t_bce - sum_bce_y*sum_ipab*sum_ipab_bce*sum_t + sum_bce_y*sum_ipab_bce*sum_t_ipab*n - sum_bce_y*sum_ipab2*sum_t_bce*n - sum_ipab*sum_ipab_bce*sum_t_bce*sum_y + sum_ipab_bce*sum_ipab_bce*sum_t*sum_y - sum_ipab_bce*sum_ipab_bce*sum_t_y*n + sum_ipab_bce*sum_ipab_y*sum_t_bce*n) AS det_bt,
    (-sum_bce*sum_bce*sum_ipab_y*sum_tt + sum_bce*sum_bce*sum_t_ipab*sum_t_y + sum_bce*sum_bce_y*sum_ipab*sum_tt - sum_bce*sum_bce_y*sum_t*sum_t_ipab - sum_bce*sum_ipab*sum_t_bce*sum_t_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_ipab_bce*sum_t*sum_t_y + sum_bce*sum_ipab_bce*sum_tt*sum_y + sum_bce*sum_ipab_y*sum_t*sum_t_bce - sum_bce*sum_t_bce*sum_t_ipab*sum_y + sum_bce2*sum_ipab*sum_t*sum_t_y - sum_bce2*sum_ipab*sum_tt*sum_y - sum_bce2*sum_ipab_y*sum_t*sum_t + sum_bce2*sum_ipab_y*sum_tt*n + sum_bce2*sum_t*sum_t_ipab*sum_y - sum_bce2*sum_t_ipab*sum_t_y*n - sum_bce_y*sum_ipab*sum_t*sum_t_bce + sum_bce_y*sum_ipab_bce*sum_t*sum_t - sum_bce_y*sum_ipab_bce*sum_tt*n + sum_bce_y*sum_t_bce*sum_t_ipab*n + sum_ipab*sum_t_bce*sum_t_bce*sum_y - sum_ipab_bce*sum_t*sum_t_bce*sum_y + sum_ipab_bce*sum_t_bce*sum_t_y*n - sum_ipab_y*sum_t_bce*sum_t_bce*n) AS det_bipab,
    (sum_bce*sum_ipab*sum_ipab_y*sum_tt - sum_bce*sum_ipab*sum_t_ipab*sum_t_y + sum_bce*sum_ipab2*sum_t*sum_t_y - sum_bce*sum_ipab2*sum_tt*sum_y - sum_bce*sum_ipab_y*sum_t*sum_t_ipab + sum_bce*sum_t_ipab*sum_t_ipab*sum_y - sum_bce_y*sum_ipab*sum_ipab*sum_tt + sum_bce_y*sum_ipab*sum_t*sum_t_ipab + sum_bce_y*sum_ipab*sum_t*sum_t_ipab - sum_bce_y*sum_ipab2*sum_t*sum_t + sum_bce_y*sum_ipab2*sum_tt*n - sum_bce_y*sum_t_ipab*sum_t_ipab*n + sum_ipab*sum_ipab*sum_t_bce*sum_t_y - sum_ipab*sum_ipab_y*sum_t*sum_t_bce - sum_ipab*sum_ipab_bce*sum_t*sum_t_y + sum_ipab*sum_ipab_bce*sum_tt*sum_y - sum_ipab*sum_t_bce*sum_t_ipab*sum_y + sum_ipab_bce*sum_ipab_y*sum_t*sum_t - sum_ipab_bce*sum_ipab_y*sum_tt*n - sum_ipab_bce*sum_t*sum_t_ipab*sum_y + sum_ipab_bce*sum_t_ipab*sum_t_y*n + sum_ipab2*sum_t*sum_t_bce*sum_y - sum_ipab2*sum_t_bce*sum_t_y*n + sum_ipab_y*sum_t_bce*sum_t_ipab*n) AS det_bbce
  FROM statistiche_di_base
),
-- Dividendo ogni determinante per il determinante principale, otteniamo
-- finalmente i 4 numeri della nostra formula.
coefficienti AS (
  SELECT
    det_a     * 1.0 / det_main AS intercetta,
    det_bt    * 1.0 / det_main AS coeff_tempo,
    det_bipab * 1.0 / det_main AS coeff_istat,
    det_bbce  * 1.0 / det_main AS coeff_bce
  FROM determinanti
)
-- Infine usiamo la formula trovata per calcolare la previsione del prezzo
-- nel primo semestre 2026 (che corrisponde a t=21, il ventunesimo semestre
-- della nostra serie). Per l'indice ISTAT e il tasso BCE di quel semestre,
-- visto che non sono ancora stati pubblicati, usiamo una stima basata
-- sull'andamento recente (vedi nota metodologica in fondo allo script).
SELECT
  'TO' AS Provincia,
  'Torino' AS Nome_Provincia,
  ROUND(intercetta, 2)   AS Intercetta,
  ROUND(coeff_tempo, 4)  AS Coefficiente_Tempo,
  ROUND(coeff_istat, 4)  AS Coefficiente_ISTAT,
  ROUND(coeff_bce, 4)    AS Coefficiente_BCE,
  ROUND(intercetta + coeff_tempo*21 + coeff_istat*103.12 + coeff_bce*2.158, 2) AS Prezzo_Previsto_H1_2026
FROM coefficienti;


-- ======================================================================
-- RISULTATI ATTESI (calcolati e verificati prima di consegnare questo file)
-- ======================================================================
-- Eseguendo i blocchi della PARTE 8 per tutte e sei le province, si
-- ottengono le seguenti previsioni per il prezzo medio del primo
-- semestre 2026 (espresso in euro al metro quadro):
--
--   Provincia | Prezzo previsto H1 2026 (EUR/mq)
--   ----------|----------------------------------
--   Bologna   | 1.680,72
--   Milano    | 2.003,16
--   Napoli    | 1.875,07
--   Palermo   |   833,61
--   Roma      | 2.018,33
--   Torino    | 1.111,76
--
-- NOTA: questi numeri derivano da un modello "lineare" puro (una formula
-- con una sola retta). Nella parte del progetto realizzata in Python, per
-- alcune province (Bologna, Napoli, Palermo, Torino) si è scoperto che un
-- modello leggermente più sofisticato (detto "polinomiale", con una curva
-- invece di una retta) descrive meglio i dati storici. I valori qui sopra
-- sono quindi leggermente diversi, ma comunque coerenti come ordine di
-- grandezza, rispetto a quelli del modello finale usato nella tesi.
--
-- Il valore di queste previsioni potrà essere verificato a settembre 2026,
-- quando l'Agenzia delle Entrate pubblicherà il dato ufficiale OMI relativo
-- al primo semestre 2026.
-- ======================================================================
