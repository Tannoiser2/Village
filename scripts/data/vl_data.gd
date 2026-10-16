class_name VLData
extends RefCounted
## Dati di Village (Inka e Markus Brand, eggertspiele/Pegasus; ed. italiana uplay.it) e delle
## espansioni Village Inn e Village Port (con gli Obiettivi di vita), ricavati dal regolamento e
## dalle immagini del modulo Tabletop Simulator.
## Le coordinate sono in pixel del tabellone (2245 x 2245); la plancia fattoria è in pixel 1024 x 1024.

# ------------------------------------------------------------------ giocatori e cubi

const COLORS := [
	{"id": 0, "key": "red", "name": "Rosso", "color": Color("#c4161c")},
	{"id": 1, "key": "yellow", "name": "Giallo", "color": Color("#f2b705")},
	{"id": 2, "key": "blue", "name": "Blu", "color": Color("#1565a6")},
	{"id": 3, "key": "white", "name": "Bianco", "color": Color("#f1ead2")},
	{"id": 4, "key": "gray", "name": "Grigio", "color": Color("#8d948d")},
]

## Cubi influenza (e peste). "pl" non è un'influenza: fa perdere 2 tempi.
const CUBES := ["pk", "br", "gr", "or"]
const CUBE := {
	"pk": {"name": "rosa", "long": "conoscenza", "color": Color("#e48cc4")},
	"br": {"name": "marrone", "long": "fede", "color": Color("#6b3d22")},
	"gr": {"name": "verde", "long": "persuasione", "color": Color("#3f9a3a")},
	"or": {"name": "arancione", "long": "abilità", "color": Color("#e8641e")},
	"pl": {"name": "nero", "long": "peste", "color": Color("#1c1c1f")},
}
const CUBE_SUPPLY := 18          # per colore nel gioco base
const CUBE_SUPPLY_INN := 5       # in più con Village Inn
const CUBE_SUPPLY_PORT := 3      # in più con Village Port
const PLAGUE := 6

## Merci (le "tessere merci"). La birra c'è con la Locanda, cacao e tè con il Porto.
const GOODS := ["horse", "ox", "plow", "wagon", "scroll", "beer", "cocoa", "tea"]
const GOOD := {
	"horse": {"name": "cavallo", "pl": "cavalli"},
	"ox": {"name": "bue", "pl": "buoi"},
	"plow": {"name": "aratro", "pl": "aratri"},
	"wagon": {"name": "carro", "pl": "carri"},
	"scroll": {"name": "pergamena", "pl": "pergamene"},
	"beer": {"name": "birra", "pl": "birre"},
	"cocoa": {"name": "cesto di cacao", "pl": "cesti di cacao"},
	"tea": {"name": "balla di tè", "pl": "balle di tè"},
}
## Generazioni dei membri della famiglia (11 per colore).
const GENS := [1, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4]

# ------------------------------------------------------------------ spazi azione

const SPACES := ["market", "travel", "harvest", "council", "family", "crafts", "church", "inn"]
const SPACE := {
	"market": {"name": "Mercato", "pos": Vector2(1020, 952)},
	"travel": {"name": "Viaggio", "pos": Vector2(1208, 866)},
	"harvest": {"name": "Mietitura", "pos": Vector2(1232, 1110)},
	"council": {"name": "Camera di Consiglio", "pos": Vector2(1447, 1342)},
	"family": {"name": "Famiglia", "pos": Vector2(1423, 1487)},
	"crafts": {"name": "Artigiani", "pos": Vector2(616, 1406)},
	"church": {"name": "Chiesa", "pos": Vector2(837, 1365)},
	"inn": {"name": "Locanda", "pos": Vector2(1360, 1943)},
}
const WELL_POS := Vector2(1880, 1372)

## Carte preparazione: cubi da mettere nel sacchetto verde (rosa, marrone, verde, arancione) e cubi per
## spazio azione (mercato, viaggio, mietitura, consiglio, famiglia, artigiani, chiesa, locanda).
## Modo: "base", "inn", "port", "innport". Tutti i cubi peste vanno sempre nel sacchetto.
const SETUP := {
	"base": {
		2: {"bag": [3, 4, 4, 3], "sp": [1, 2, 2, 2, 3, 5, 3, 0]},
		3: {"bag": [4, 4, 5, 4], "sp": [1, 2, 3, 2, 4, 6, 3, 0]},
		4: {"bag": [5, 5, 5, 5], "sp": [1, 2, 4, 3, 4, 7, 3, 0]},
		5: {"bag": [6, 6, 7, 7], "sp": [1, 3, 4, 4, 6, 8, 4, 0]},
	},
	"inn": {
		2: {"bag": [4, 5, 5, 4], "sp": [1, 2, 3, 2, 3, 6, 3, 2]},
		3: {"bag": [5, 5, 6, 5], "sp": [1, 2, 4, 2, 4, 6, 3, 2]},
		4: {"bag": [6, 6, 6, 6], "sp": [1, 2, 4, 3, 5, 7, 3, 3]},
		5: {"bag": [7, 7, 8, 8], "sp": [1, 3, 4, 4, 6, 10, 4, 3]},
	},
	"port": {
		2: {"bag": [3, 4, 4, 3], "sp": [1, 2, 2, 2, 3, 5, 3, 0]},
		3: {"bag": [5, 5, 6, 5], "sp": [1, 3, 4, 2, 4, 7, 3, 0]},
		4: {"bag": [6, 6, 6, 6], "sp": [1, 4, 4, 3, 5, 8, 3, 0]},
		5: {"bag": [6, 6, 7, 7], "sp": [1, 4, 4, 4, 5, 8, 4, 0]},
	},
	"innport": {
		2: {"bag": [4, 5, 5, 4], "sp": [1, 2, 3, 2, 3, 6, 3, 2]},
		3: {"bag": [6, 6, 6, 6], "sp": [1, 3, 4, 2, 4, 7, 3, 3]},
		4: {"bag": [7, 7, 7, 7], "sp": [1, 4, 5, 3, 5, 8, 3, 3]},
		5: {"bag": [7, 7, 8, 8], "sp": [1, 4, 4, 4, 5, 10, 4, 3]},
	},
}

# ------------------------------------------------------------------ artigiani

## Edifici artigianali: tempo per addestrare un familiare, tempo per produrre, costo d'acquisto.
## buy: cubi influenza oppure "grain" (sacchi di grano). Il mulino dà 2 monete per 2 tempi e 2 grani.
const CRAFTS := ["forge", "wagon", "stable", "office", "brewery", "mill"]
const CRAFT := {
	"forge": {"name": "Fucina", "good": "plow", "train": 3, "make": 3, "buy": ["or", "pk"], "pos": Vector2(800, 828)},
	"wagon": {"name": "Carradore", "good": "wagon", "train": 2, "make": 2, "buy": ["or", "pk"], "pos": Vector2(850, 1188)},
	"stable": {"name": "Stalle", "good": "horse", "train": 3, "make": 3, "grain": 3, "pos": Vector2(485, 1348)},
	"office": {"name": "Ufficio", "good": "scroll", "train": 2, "make": 2, "buy": ["pk"], "pos": Vector2(445, 1602)},
	"brewery": {"name": "Birrificio", "good": "beer", "qty": 2, "train": 3, "make": 3, "grain": 3, "pos": Vector2(237, 2045)},
	"mill": {"name": "Mulino", "pos": Vector2(330, 990)},
}

# ------------------------------------------------------------------ consiglio e chiesa

const COUNCIL_TIME := [1, 2, 2, 3]            # tempo per entrare nel livello 1, 2, 3, 4
const COUNCIL_PTS := [0, 2, 4, 6]             # punti finali per livello
const COUNCIL_POS := [Vector2(1715, 1215), Vector2(1835, 1170), Vector2(1945, 1130), Vector2(2050, 1095)]
const NEXT_POS := Vector2(1720, 1285)
const PRIV := ["", "Diventa primo giocatore al prossimo round", "2 cubi influenza a scelta", "1 merce a scelta", "Paga 1 moneta: 3 punti prestigio"]

const WINDOW_PTS := [2, 3, 4, 6]              # vetrate da destra a sinistra
const WINDOW_COST := [1, 2, 4]                # grano per salire alla vetrata successiva
const WINDOW_POS := [Vector2(1020, 1855), Vector2(910, 1915), Vector2(785, 1990), Vector2(520, 1955)]
const BAG_POS := Vector2(1100, 1520)
const MONKS := 4

# ------------------------------------------------------------------ viaggio (gioco base)

const CITIES := ["A", "B", "C", "D", "E", "F"]
const CITY := {
	"A": {"name": "Abbazia", "reward": "pp3", "pos": Vector2(1255, 440)},
	"B": {"name": "Rocca del Nord", "reward": "coin", "pos": Vector2(1460, 200), "castle": true},
	"C": {"name": "Castello Grande", "reward": "cubes2", "pos": Vector2(1940, 220), "castle": true},
	"D": {"name": "Borgo", "reward": "cubes2", "pos": Vector2(1660, 470)},
	"E": {"name": "Rocca dell'Est", "reward": "coin", "pos": Vector2(1990, 530), "castle": true},
	"F": {"name": "Mulino del Sud", "reward": "pp3", "pos": Vector2(1720, 690)},
	"G": {"name": "Porta del villaggio", "pos": Vector2(1270, 770)},
}
## Strade: città, città, cubi da pagare (oltre a 2 tempi e 1 carro). G è la porta del villaggio.
const ROADS := [
	["G", "A", ["br", "br"]], ["G", "F", ["pk", "pk"]],
	["A", "B", ["pk", "or", "or"]], ["A", "D", ["br", "or", "pk"]], ["B", "D", ["br", "pk", "pk"]],
	["B", "C", ["or", "br", "br"]], ["C", "D", ["br", "or", "pk"]], ["C", "E", ["or", "pk", "pk"]],
	["D", "E", ["br", "or", "or"]], ["D", "F", ["or", "or"]], ["E", "F", ["pk", "br", "br"]],
]
const TRAVEL_PTS := [0, 1, 3, 6, 10, 14, 18]
const TRAVELLER_PTS := [0, 3, 6, 10, 15, 20, 25]

# ------------------------------------------------------------------ cronache e tombe

const SECTIONS := ["council", "crafts", "travel", "church", "farm"]
const SECTION := {
	"council": {"name": "Camera di Consiglio", "color": Color("#c4371f")},
	"crafts": {"name": "Artigiani", "color": Color("#d8a915")},
	"travel": {"name": "Viaggio", "color": Color("#3b8a2c")},
	"church": {"name": "Chiesa", "color": Color("#5a3519")},
	"farm": {"name": "Fattoria", "color": Color("#9a3c95")},
}
## Spazi delle cronache: il numero è quello stampato (0 = sempre libero; altrimenti coperto se ci sono
## meno giocatori). Piccole = tabellone base (2-4 giocatori), grandi = tessera per la Locanda o per 5.
const CHRON_SMALL := {"council": [0, 3], "crafts": [0, 0, 3], "travel": [0, 4], "church": [0, 0, 3], "farm": [0, 0, 0, 3, 4]}
const GRAVES_SMALL := [0, 0, 0, 3, 4]
const CHRON_BIG := {"council": [0, 3, 5], "crafts": [0, 0, 3, 5], "travel": [0, 4], "church": [0, 0, 3, 5], "farm": [0, 0, 0, 3, 4, 5]}
const GRAVES_BIG := [0, 0, 0, 3, 4, 5]
const CHRON_SMALL_POS := {
	"council": [Vector2(1475, 1670), Vector2(1555, 1670)],
	"crafts": [Vector2(1470, 1790), Vector2(1550, 1790), Vector2(1630, 1790)],
	"travel": [Vector2(1475, 1920), Vector2(1555, 1920)],
	"church": [Vector2(1765, 1665), Vector2(1835, 1660), Vector2(1905, 1660)],
	"farm": [Vector2(1765, 1790), Vector2(1840, 1785), Vector2(1910, 1785), Vector2(1795, 1900), Vector2(1875, 1900)],
}
const GRAVES_SMALL_POS := [Vector2(250, 1810), Vector2(330, 1855), Vector2(400, 1910), Vector2(210, 1945), Vector2(280, 1985)]
## Tessere grandi: coordinate nelle loro immagini (cronache 1400 x 980, tombe 406 x 512).
const CHRON_BIG_PX := Vector2(1400, 980)
const CHRON_BIG_POS := {
	"council": [Vector2(368, 210), Vector2(462, 210), Vector2(553, 210)],
	"crafts": [Vector2(329, 378), Vector2(420, 378), Vector2(508, 378), Vector2(592, 378)],
	"travel": [Vector2(368, 539), Vector2(462, 539)],
	"church": [Vector2(725, 210), Vector2(812, 210), Vector2(900, 210), Vector2(987, 210)],
	"farm": [Vector2(763, 371), Vector2(854, 371), Vector2(945, 371), Vector2(767, 539), Vector2(858, 539), Vector2(949, 539)],
}
const GRAVES_BIG_PX := Vector2(406, 512)
const GRAVES_BIG_POS := [Vector2(175, 125), Vector2(255, 175), Vector2(325, 225), Vector2(110, 250), Vector2(170, 305), Vector2(240, 350)]
const CHRON_PTS := [0, 0, 0, 4, 7, 12]        # 3 = 4 punti, 4 = 7, 5 o più = 12
const ARTIST_PTS := [0, 0, 3, 7, 12, 18, 21]  # con l'Artista

# ------------------------------------------------------------------ mercato

## Spazi davanti alle bancarelle (il 4° e il 5° sono quelli segnati "3" e "4") e coda d'attesa.
const MARKET_FRONT_POS := [Vector2(482, 356), Vector2(622, 340), Vector2(761, 345), Vector2(346, 404), Vector2(389, 534)]
const MARKET_QUEUE_POS := [Vector2(848, 508), Vector2(968, 562), Vector2(915, 675), Vector2(1032, 735), Vector2(997, 850)]

## Clienti: indice nel foglio delle immagini, punti, richiesta (merci e grano).
const CUSTOMERS := [
	{"img": 0, "pp": 3, "need": {"ox": 1}},
	{"img": 1, "pp": 3, "need": {"grain": 3}},
	{"img": 2, "pp": 5, "need": {"plow": 1, "ox": 1}},
	{"img": 3, "pp": 6, "need": {"scroll": 1, "horse": 1}},
	{"img": 4, "pp": 3, "need": {"wagon": 1}},
	{"img": 5, "pp": 4, "need": {"scroll": 1, "plow": 1}},
	{"img": 6, "pp": 4, "need": {"scroll": 2}},
	{"img": 7, "pp": 4, "need": {"horse": 1}},
	{"img": 8, "pp": 3, "need": {"ox": 1}},
	{"img": 11, "pp": 3, "need": {"ox": 1}},
	{"img": 14, "pp": 3, "need": {"wagon": 1}},
	{"img": 15, "pp": 4, "need": {"horse": 1}},
	{"img": 16, "pp": 3, "need": {"grain": 1, "scroll": 1}},
	{"img": 17, "pp": 4, "need": {"grain": 4}},
	{"img": 18, "pp": 6, "need": {"wagon": 1, "ox": 1}},
	{"img": 19, "pp": 5, "need": {"wagon": 1, "plow": 1}},
	{"img": 20, "pp": 3, "need": {"grain": 3}},
	{"img": 21, "pp": 6, "need": {"horse": 1, "plow": 1}},
	{"img": 22, "pp": 4, "need": {"horse": 1}},
	{"img": 23, "pp": 5, "need": {"scroll": 1, "ox": 1}},
	{"img": 24, "pp": 2, "need": {"plow": 1}},
	{"img": 25, "pp": 6, "need": {"grain": 2, "horse": 1}},
	{"img": 26, "pp": 3, "need": {"grain": 1, "scroll": 1}},
	{"img": 27, "pp": 3, "need": {"grain": 1, "plow": 1}},
	# Village Inn
	{"img": 9, "pp": 4, "need": {"beer": 1, "scroll": 1}, "inn": true},
	{"img": 10, "pp": 4, "need": {"beer": 2}, "inn": true},
	{"img": 12, "pp": 3, "need": {"grain": 1, "beer": 1}, "inn": true},
	{"img": 13, "pp": 2, "need": {"beer": 1}, "inn": true},
]

# ------------------------------------------------------------------ Locanda: abitanti

## kind: "end" = si tiene fino al punteggio finale; "any" = si gioca quando si vuole nel proprio turno;
## gli altri hanno un momento preciso. cost: "coin", "beer", "beer2".
## set: "inn" (sempre con la Locanda), "innonly" (solo senza Porto), "port" (solo con il Porto).
const VILLAGERS := [
	{"id": 0, "key": "guild", "name": "Maestro di gilda", "cost": "beer", "kind": "end", "set": "inn", "text": "A fine partita: cubi arancioni rimasti nella fattoria, 1 = 2 punti, 2 = 4, 3 = 6 (più di 3 = niente; le monete non valgono)."},
	{"id": 1, "key": "scribe", "name": "Scrivano", "cost": "coin", "kind": "any", "set": "inn", "text": "Prendi 2 pergamene."},
	{"id": 2, "key": "wagonmaker", "name": "Carradore", "cost": "coin", "kind": "any", "set": "inn", "text": "Prendi 1 carro."},
	{"id": 3, "key": "cutpurse", "name": "Borsaiola", "cost": "beer", "kind": "end", "set": "inn", "text": "Dopo il punteggio finale: 6 punti se nessuno ha meno punti di te, altrimenti 3."},
	{"id": 4, "key": "lostson", "name": "Figliol prodigo", "cost": "beer2", "kind": "any", "set": "inn", "text": "3 punti prestigio e un'azione Famiglia in più."},
	{"id": 5, "key": "cattle", "name": "Allevatore", "cost": "coin", "kind": "any", "set": "inn", "text": "Prendi 1 cavallo oppure 1 bue."},
	{"id": 6, "key": "blacksmith", "name": "Fabbro", "cost": "coin", "kind": "any", "set": "inn", "text": "Prendi 2 aratri."},
	{"id": 7, "key": "toll", "name": "Gabelliere", "cost": "beer", "kind": "travel", "set": "innonly", "text": "In un'azione Viaggio: ti sposti in una città vicina senza pagare il viaggio (cubi, 2 tempi, carro)."},
	{"id": 8, "key": "councilman", "name": "Consigliere", "cost": "beer2", "kind": "any", "set": "inn", "text": "Serve un tuo familiare nella Camera di Consiglio: ottieni 2 privilegi del suo livello o inferiori (anche lo stesso due volte)."},
	{"id": 9, "key": "traveller", "name": "Viaggiatore", "cost": "beer2", "kind": "end", "set": "innonly", "text": "A fine partita le città visitate valgono 1 = 3, 2 = 6, 3 = 10, 4 = 15, 5 = 20, 6 = 25 punti."},
	{"id": 10, "key": "priest", "name": "Prete", "cost": "beer", "kind": "mass", "set": "inn", "text": "All'inizio di una messa: nessuno compra familiari dal sacchetto nero; scegli tu i 4 personaggi estratti."},
	{"id": 11, "key": "nun", "name": "Suora", "cost": "beer", "kind": "end", "set": "inn", "text": "A fine partita: cubi marroni rimasti, 1 = 2 punti, 2 = 4, 3 = 6 (più di 3 = niente)."},
	{"id": 12, "key": "miller", "name": "Mugnaio", "cost": "beer", "kind": "mill", "set": "inn", "text": "Al mulino: una volta prendi 5 monete invece di 2."},
	{"id": 13, "key": "medico", "name": "Medico", "cost": "beer2", "kind": "end", "set": "inn", "text": "A fine partita: 1 punto per ogni familiare vivo (fattoria, sacchetto nero, tabellone)."},
	{"id": 14, "key": "barker", "name": "Imbonitore", "cost": "beer", "kind": "market", "set": "inn", "text": "All'inizio di un giorno di mercato: puoi servire anche i clienti in coda."},
	{"id": 15, "key": "artist", "name": "Artista", "cost": "beer2", "kind": "end", "set": "inn", "text": "Cronache: 2 familiari = 3 punti, 3 = 7, 4 = 12, 5 = 18, 6 = 21."},
	{"id": 16, "key": "herb", "name": "Erborista", "cost": "beer", "kind": "any", "set": "inn", "text": "2 punti prestigio; puoi spostare il segnatempo subito prima o subito dopo il ponte."},
	{"id": 17, "key": "farmhand", "name": "Bracciante", "cost": "beer", "kind": "any", "set": "inn", "text": "2 punti prestigio e la fattoria si riempie di grano (5 sacchi)."},
	{"id": 18, "key": "manciple", "name": "Economo", "cost": "beer2", "kind": "end", "set": "inn", "text": "A fine partita: 2 punti per ogni tipo di merce che possiedi."},
	{"id": 19, "key": "oldman", "name": "Vecchio saggio", "cost": "beer", "kind": "oldman", "set": "inn", "text": "Al posto di prendere un cubo: 3 punti prestigio e un'azione a scelta gratuita."},
	{"id": 20, "key": "count", "name": "Conte", "cost": "beer2", "kind": "end", "set": "innonly", "text": "A fine partita: 2 punti per ogni castello con un tuo segnalino (le due città da 1 moneta e quella in alto a destra)."},
	{"id": 21, "key": "scholar", "name": "Erudito", "cost": "beer", "kind": "end", "set": "inn", "text": "A fine partita: cubi rosa rimasti, 1 = 2 punti, 2 = 4, 3 = 6 (più di 3 = niente)."},
	{"id": 22, "key": "juggler", "name": "Giocoliere", "cost": "beer", "kind": "juggler", "set": "inn", "text": "Dopo la tua azione: 2 punti prestigio e un'altra azione."},
	{"id": 23, "key": "noble", "name": "Nobildonna", "cost": "coin", "kind": "any", "set": "inn", "text": "2 punti prestigio; scegli una carta da uno dei 3 mazzi degli abitanti."},
	{"id": 24, "key": "mayor", "name": "Sindaco", "cost": "beer", "kind": "end", "set": "inn", "text": "A fine partita: cubi verdi rimasti, 1 = 2 punti, 2 = 4, 3 = 6 (più di 3 = niente)."},
	{"id": 25, "key": "messenger", "name": "Messaggero", "cost": "beer", "kind": "any", "set": "innonly", "text": "Metti un tuo segnalino su una città senza un tuo segnalino e prendi il suo premio."},
	{"id": 26, "key": "peasant", "name": "Contadina", "cost": "beer", "kind": "end", "set": "inn", "text": "A fine partita: 1 punto per ogni sacco di grano nella fattoria."},
	{"id": 27, "key": "quartermaster", "name": "Quartiermastro", "cost": "beer2", "kind": "load", "set": "port", "text": "Quando carichi la nave: una volta puoi caricare 2 pezzi dello stesso tipo."},
	{"id": 28, "key": "admiral", "name": "Ammiraglio", "cost": "beer", "kind": "captain", "set": "port", "text": "Fa da capitano: ogni cubo di qualsiasi colore = 1 passo in più."},
	{"id": 29, "key": "cartographer", "name": "Cartografo", "cost": "beer2", "kind": "sail", "set": "port", "text": "In un viaggio per mare: porti la nave su un'isola qualsiasi senza costi (serve un capitano)."},
	{"id": 30, "key": "helmsman", "name": "Timoniere", "cost": "beer", "kind": "captain", "set": "port", "text": "Insieme a un capitano: un passo gratuito in più."},
	{"id": 31, "key": "abbot", "name": "Abate", "cost": "beer", "kind": "any", "set": "inn", "text": "Sposta un tuo familiare dalla chiesa alla vetrata più a sinistra, senza pagare grano."},
	{"id": 32, "key": "scrap", "name": "Rigattiere", "cost": "beer2", "kind": "scrap", "set": "inn", "text": "A fine giorno di mercato: prendi gratis un cliente rimasto davanti alle bancarelle."},
	{"id": 33, "key": "bard", "name": "Bardo", "cost": "beer", "kind": "bard", "set": "inn", "text": "Quando muore un tuo familiare: va nelle cronache in più, ovunque sia morto."},
]
const DECKS := 3
const DECK_SIZE := 10

# ------------------------------------------------------------------ Porto

## Mare: nodi (P = porto, T = acque del tempo, isole). pos in pixel del tabellone.
const SEA := {
	"P": {"kind": "port", "pos": Vector2(1374, 690)},
	"T1": {"kind": "time", "pos": Vector2(1306, 313)},
	"T2": {"kind": "time", "pos": Vector2(1300, 546)},
	"T3": {"kind": "time", "pos": Vector2(1500, 588)},
	"T4": {"kind": "time", "pos": Vector2(2038, 378)},
	"T5": {"kind": "time", "pos": Vector2(1931, 505)},
	"T6": {"kind": "time", "pos": Vector2(1680, 760)},
	"NW": {"kind": "island", "name": "Isola del mercante", "pos": Vector2(1128, 240), "sell": {"ox": 4, "wagon": 4, "plow": 3},
		"mission": {"cubes": ["br", "or"]}, "mpp": 5, "mpos": Vector2(1248, 228)},
	"CH": {"kind": "island", "name": "Isola del tesoro", "pos": Vector2(1500, 278), "stack": "chest", "spos": Vector2(1633, 165)},
	"NE": {"kind": "island", "name": "Isola lontana", "pos": Vector2(1873, 218), "mission": {"wagon": 1, "cubes": ["br"]}, "mpp": 12, "mpos": Vector2(2051, 228)},
	"CO": {"kind": "island", "name": "Isola del cacao", "pos": Vector2(1153, 490), "stack": "cocoa", "spos": Vector2(1153, 410),
		"mission": {"wagon": 1, "cubes": ["br"]}, "mpp": 6, "mpos": Vector2(1360, 465)},
	"TE": {"kind": "island", "name": "Isola del tè", "pos": Vector2(1593, 465), "stack": "tea", "spos": Vector2(1640, 378),
		"mission": {"wagon": 1, "cubes": ["br"]}, "mpp": 6, "mpos": Vector2(1838, 410)},
	"SE": {"kind": "island", "name": "Isola del sud", "pos": Vector2(1986, 700), "sell": {"horse": 5, "scroll": 3, "grain": 2},
		"mission": {"cubes": ["pk", "br"]}, "mpp": 5, "mpos": Vector2(1868, 665)},
}
const SEA_EDGES := [["P", "T2"], ["P", "T3"], ["P", "T6"], ["T2", "CO"], ["T2", "T3"], ["CO", "NW"], ["NW", "T1"], ["T1", "T3"],
	["CH", "T3"], ["T3", "TE"], ["T3", "T6"], ["TE", "T5"], ["T5", "T4"], ["T5", "SE"], ["T4", "NE"], ["T6", "SE"]]
const ISLANDS := ["NW", "CH", "NE", "CO", "TE", "SE"]
const MISSIONS := ["NW", "NE", "CO", "TE", "SE"]
const BURIAL_PTS := [2, 1, 0]
const BURIAL_POS := [Vector2(2058, 500), Vector2(2069, 563), Vector2(2079, 623)]
const STALL_POS := {"cocoa": Vector2(960, 325), "tea": Vector2(960, 425)}
const COCOA_PP := 7
const TEA_PP := 5
const CHESTS := [3, 3, 3, 4, 4, 5]
const PORT_STACK := {2: 3, 3: 4, 4: 5, 5: 6}
## Pezzi che si possono caricare sulla nave in porto (cacao, tè e forzieri solo alle isole).
const LOADABLE := ["horse", "ox", "plow", "wagon", "scroll", "grain", "member"]

## Capitani: costo in monete; step = cubi da pagare per ogni passo oltre il primo (gratuito).
## "any" = un cubo di qualsiasi colore; n = quanti passi vale il pagamento.
const CAPTAINS := [
	{"cost": 1, "pay": ["or", "pk"], "steps": 1}, {"cost": 1, "pay": ["or", "pk"], "steps": 1},
	{"cost": 1, "pay": ["or", "pk"], "steps": 1}, {"cost": 1, "pay": ["or", "pk"], "steps": 1},
	{"cost": 1, "pay": ["or", "pk"], "steps": 1},
	{"cost": 2, "pay": ["br"], "steps": 1}, {"cost": 2, "pay": ["gr"], "steps": 1}, {"cost": 2, "pay": ["or"], "steps": 1},
	{"cost": 2, "pay": ["pk"], "steps": 1}, {"cost": 2, "pay": ["any", "any"], "steps": 1},
	{"cost": 3, "pay": ["br"], "steps": 2}, {"cost": 3, "pay": ["gr"], "steps": 2}, {"cost": 3, "pay": ["or"], "steps": 2},
	{"cost": 3, "pay": ["pk"], "steps": 2}, {"cost": 3, "pay": ["any", "any"], "steps": 2},
]
const ADMIRAL := {"cost": 0, "pay": ["any"], "steps": 1}

# ------------------------------------------------------------------ Obiettivi di vita

## Argento (5 punti): basta possedere i pezzi indicati. Oro (8 punti): condizioni particolari.
## no: in quali combinazioni la carta si toglie ("base", "inn", "port", "innport").
const GOALS_SILVER := [
	{"key": "brewer", "name": "Birraio", "need": {"wagon": 1, "beer": 4}, "no": ["base", "port"]},
	{"key": "farmer", "name": "Contadino", "need": {"plow": 1, "ox": 2, "grain": 5}},
	{"key": "aristocrat", "name": "Aristocratico", "need": {"coin": 7}},
	{"key": "explorer", "name": "Esploratore", "need": {}, "no": ["base", "inn"], "text": "Sulla nave: un cavallo, un familiare e un forziere."},
	{"key": "knight", "name": "Cavaliere", "need": {"horse": 1, "next": 1, "coin": 3}},
	{"key": "writer", "name": "Scrittore", "need": {"scroll": 3, "pk": 1, "or": 1, "br": 1, "gr": 1}},
	{"key": "bailiff", "name": "Balivo", "need": {"scroll": 1, "next": 1, "gr": 2, "pk": 2}},
	{"key": "carter", "name": "Carrettiere", "need": {"horse": 2, "wagon": 2}},
]
const GOALS_GOLD := [
	{"key": "salesman", "name": "Venditore ambulante", "no": ["port", "innport"], "text": "Un tuo familiare nel Castello Grande (in alto a destra sulla mappa) e almeno 2 clienti serviti."},
	{"key": "master", "name": "Maestro artigiano", "text": "Almeno 4 familiari negli artigiani (negli edifici o nelle cronache degli artigiani)."},
	{"key": "innkeeper", "name": "Oste", "no": ["base", "port"], "text": "Almeno 4 carte abitante in mano (non giocate)."},
	{"key": "secretary", "name": "Segretario", "text": "Un tuo familiare al 4° livello della Camera di Consiglio e il segnalino del prossimo primo giocatore."},
	{"key": "acolyte", "name": "Accolito", "text": "Un tuo familiare della 4ª generazione in chiesa."},
	{"key": "merchant", "name": "Mercante", "text": "Almeno 6 clienti serviti."},
	{"key": "saint", "name": "Santo", "text": "Tre familiari in chiesa, uno su ciascuna delle 3 vetrate più a destra."},
	{"key": "missionary", "name": "Missionario", "no": ["base", "inn"], "text": "Familiari su almeno 2 chiese missionarie."},
	{"key": "historian", "name": "Storico", "text": "Familiari in almeno 4 sezioni delle cronache (il Bardo non conta)."},
]
const SILVER_PP := 5
const GOLD_PP := 8

# ------------------------------------------------------------------ plancia fattoria (pixel 1024)

## Nuvole del tempo della vita: 0 = subito a destra del ponte, poi in senso orario; dopo la 9 si
## attraversa il ponte e muore un familiare.
const TIME_POS := [Vector2(690, 80), Vector2(945, 225), Vector2(935, 490), Vector2(930, 770), Vector2(690, 925),
	Vector2(345, 925), Vector2(85, 765), Vector2(88, 490), Vector2(90, 230), Vector2(345, 75)]
const TIME_STEPS := 10
const GRAIN_POS := [Vector2(268, 775), Vector2(397, 775), Vector2(526, 775), Vector2(655, 775), Vector2(785, 775)]
const GRAIN_MAX := 5
const YARD := Rect2(520, 150, 360, 260)

# ------------------------------------------------------------------ segnapunti

## Percorso del prestigio lungo il bordo del tabellone: angoli e multipli di 5.
const TRACK_ANCHORS := [
	Vector2(52, 52), Vector2(558, 64), Vector2(1115, 52), Vector2(1638, 46), Vector2(2196, 46),
	Vector2(2196, 580), Vector2(2196, 1127), Vector2(2196, 1673), Vector2(2196, 2196),
	Vector2(1650, 2196), Vector2(1115, 2196), Vector2(569, 2196), Vector2(52, 2196),
	Vector2(52, 1661), Vector2(52, 1115), Vector2(52, 604), Vector2(52, 52),
]

const BOARD_PX := 2245.0


static func track_pos(pp: int) -> Vector2:
	var v := posmod(pp, 80)
	var seg := v / 5
	var t := float(v % 5) / 5.0
	return TRACK_ANCHORS[seg].lerp(TRACK_ANCHORS[seg + 1], t)


static func cube_name(c: String) -> String:
	return CUBE[c]["name"] if CUBE.has(c) else "moneta"


static func good_name(g: String, n := 1) -> String:
	if g == "grain":
		return "sacco di grano" if n == 1 else "sacchi di grano"
	if g == "coin":
		return "moneta" if n == 1 else "monete"
	if GOOD.has(g):
		return GOOD[g]["name"] if n == 1 else GOOD[g]["pl"]
	return g


static func villager(id: int) -> Dictionary:
	return VILLAGERS[id]


static func cost_text(cost: String) -> String:
	match cost:
		"coin": return "1 moneta"
		"beer": return "1 birra"
		"beer2": return "2 birre"
	return cost


static func sea_neighbors(node: String) -> Array:
	var out := []
	for e in SEA_EDGES:
		if e[0] == node:
			out.append(e[1])
		elif e[1] == node:
			out.append(e[0])
	return out


static func road(a: String, b: String) -> Array:
	for r in ROADS:
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return []


static func city_neighbors(c: String) -> Array:
	var out := []
	for r in ROADS:
		if r[0] == c:
			out.append(r[1])
		elif r[1] == c:
			out.append(r[0])
	return out
