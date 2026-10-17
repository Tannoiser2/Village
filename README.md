# Village — adattamento digitale (Godot 4)

Versione digitale per uso personale di **Village** di Inka e Markus Brand (illustrazioni di Dennis
Lohausen, © eggertspiele / Pegasus Spiele; edizione italiana uplay.it), con le espansioni **Village Inn**,
**Village Port** e gli **Obiettivi di vita**. Componenti, illustrazioni e regole © dei rispettivi autori:
le immagini vengono dal modulo Tabletop Simulator e non vanno distribuite pubblicamente.

**Gioca nel browser:** https://tannoiser2.github.io/Village/

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Da 2 a 5 famiglie** (Rosso, Giallo, Blu, Bianco, Grigio), ognuna Umano, IA o Assente. Con più
  persone sullo stesso dispositivo si gioca a turno: prima di ogni decisione una schermata "tocca a…"
  nasconde carte e obiettivi segreti.
- **Tema da villaggio medievale**: pergamene, assi di legno, rosso dei tetti e verde dei prati presi dal
  tabellone; titoli in *Uncial Antiqua* (come i nomi sulle carte), testo in *IM Fell English*, numeri e
  pulsanti in *Almendra* (tutti con licenza OFL, in `assets/fonts`).
- **Musica ed effetti**: una danza medievale con liuto, flauto dolce, bordone e tamburello in loop, e
  campana della messa, rintocchi, monete, pedine di legno. Si spengono separatamente (Musica / Effetti,
  nel menu e in partita). Tutto è sintetizzato da `tools/sintetizza_audio.py`, senza campioni esterni.
- **Tabellone in 3D** sul tavolo, con i meeple del modulo TTS con il numero della generazione. I cubi si
  prendono cliccandoli direttamente sulla mappa (un mucchietto per colore, con un anello luminoso).
  Trascina per ruotare, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina) per spostare;
  doppio clic su un punto vuoto (o tasto Home) per tornare alla vista iniziale.
- **Plance originali delle famiglie** nel pannello di sinistra: segnatempo sulle nuvole, grano nei campi,
  familiari nell'aia, cubi influenza sul muro di casa, segnalini del primo giocatore; accanto monete,
  merci, clienti serviti, carte e nave.
- **Cronache del villaggio** e tombe anonime sul tabellone (in 5 giocatori coperte dalle tessere grandi);
  con la Locanda, che copre quelle stampate, si vedono nel pannello di destra con il disegno originale.
  A destra anche mercato, Locanda, i tre mazzi di capitani del Porto e l'ultima azione; il racconto
  completo è nel *Diario*.
- **Viaggio per mare guidato**: si clicca la carta del capitano da ingaggiare, si carica la nave, poi si
  clicca un'acqua vicina per ogni passo (lettere e nomi sulla mappa, la rotta numerata e la nave in
  anteprima, costi in tempo e cubi sempre in vista) e si chiude con *Termina il movimento* (o *Termina e
  approda* su un'isola).
- **Regole complete** del gioco base (regolamento italiano): cubi influenza e peste dal sacchetto verde,
  pozzo, tempo della vita e morte con le cronache e le tombe anonime, mietitura, famiglia, artigiani
  (addestrare e produrre o comprare con i cubi), mulino, giorno di mercato con la coda dei clienti,
  viaggio con premi e segnalini sulle città, Camera di Consiglio e privilegi, chiesa e messa (acquisto
  dal sacchetto nero, salita delle vetrate, maggioranza), monete come jolly, fine partita con le ultime
  azioni e punteggio finale con gli spareggi. Spazi coperti con meno giocatori, cronache e tombe grandi
  in 5.
- **Village Inn**: Birrificio, Locanda con i tre mazzi di 10 abitanti, le 30 carte (tutte), i 4 clienti
  della birra, il quinto colore, le carte preparazione della Locanda.
- **Village Port**: mappa del mare con acque del tempo e isole, 15 capitani, carico della nave (fino a 3
  pezzi diversi), vendite sulle isole, cacao, tè e forzieri, chiese missionarie, sepolture in mare e le
  quattro carte abitante del Porto (Ammiraglio, Timoniere, Quartiermastro, Cartografo).
- **Obiettivi di vita**: un obiettivo d'argento e uno d'oro segreti per famiglia, tolti secondo le
  espansioni in gioco; si incassano da soli appena raggiunti.
- **IA** su tre livelli: prova ogni mossa su una copia della partita, risolve le scelte che restano
  (privilegi, premi, prima vendita, isole…) e valuta la posizione con una stima dei punti finali più il
  valore delle risorse, che cala man mano che cronache e tombe si riempiono. I pesi sono tarati con
  partite IA contro IA (`tests/sim.gd`). Non guarda le carte coperte degli altri.
- **Aiuti**: la mossa consigliata dall'IA evidenziata in verde (si spegne con *Niente consigli
  dell'IA* fra le espansioni e opzioni), ultima azione sempre in vista, diario completo, regole in breve con una
  scheda per ogni espansione.

### Semplificazioni
- Le carte abitante "quando vuoi" si giocano nel proprio turno (prima di prendere il cubo o a fine
  turno), non durante il mercato o la messa degli altri.
- Il forziere si apre (e diventa monete) appena la nave rientra in porto.
- Gli obiettivi di vita si rivelano da soli appena sono soddisfatti.
- I clienti promozionali del modulo TTS non sono usati: solo i 24 del gioco base e i 4 della Locanda.

## Gioco online
Dal menu, **GIOCA ONLINE** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database, piano gratuito), con le stanze sotto `village/rooms` (le regole del database
coprono già ogni gioco con la regola generica `$game`: `firebase/database.rules.json`).

- **Chi crea la stanza** sceglie prima nel menu famiglie, espansioni e livello dell'IA: i colori su UMANO
  diventano i posti per gli amici (il primo è il suo). Scrive il nome, preme *Crea una stanza* e comunica
  il codice di 4 lettere. Quando ci sono tutti preme *Si comincia!*: i posti liberi li gioca l'IA.
- **Gli amici** scrivono il nome e il codice e premono *Entra*.
- La partita viaggia come registro di mosse: ogni dispositivo gioca la stessa partita con lo stesso seme.
  Chi chiude la pagina può rientrare con lo stesso codice; se qualcuno non risponde per un minuto, al
  suo posto gioca l'IA finché non torna.

## Struttura
- `scripts/data/vl_data.gd` — dati: carte preparazione, edifici, strade e città, cronache, clienti,
  abitanti, mappa del mare, capitani, obiettivi, coordinate sul tabellone.
- `scripts/core/state.gd` — stato della partita e regole immediate (pagamenti, azioni, mercato, messa,
  morte, punteggio). `engine.gd` — round, turni e decisioni. `ai.gd` — IA.
- `scripts/ui/` — menu, vista di gioco, tabellone 3D, plance delle famiglie, cronache, regole, tema grafico, audio.
- `scripts/net/` — Firebase (REST) e partita online in lockstep.
- `tools/prepara_asset.py` — ricava tabelloni (con Locanda, Birrificio e Porto sovrapposti come nel
  modulo TTS), carte, segnalini e modelli dal modulo TTS; `tools/sintetizza_audio.py` — musica ed effetti.
- `tests/` — `sim.gd` (partite IA contro IA), `shot.gd` (screenshot), `online_play.gd` +
  `firebase_mock.py` (partita online completa su un finto Firebase locale).

## Pubblicazione
A ogni push su `main` la GitHub Action `.github/workflows/pages.yml` esporta la versione web con Godot
4.7 e la pubblica su GitHub Pages (impostazioni del repository → Pages → Source: *GitHub Actions*).
La scheda per la pagina della ludoteca è in `ludoteca/scheda.json`.
