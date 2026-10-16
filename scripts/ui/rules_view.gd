extends Control
## Regole in breve (dal regolamento italiano del gioco base e da quelli delle espansioni, tradotti).
## Si apre dal menu o durante la partita. Quattro schede: base, Locanda, Porto, Obiettivi di vita.

var main
var embedded := false
var on_close: Callable
var text: RichTextLabel
var tabs := []

const H := "[font_size=30][font=res://assets/fonts/UncialAntiqua-Regular.ttf][color=#8a2a14]%s[/color][/font][/font_size]"


func _ready() -> void:
	size = Vector2(1920, 1080)
	if not embedded:
		var bg := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = UI.tex("res://assets/board/board_base.jpg")
		at.region = Rect2(0, 0, 2048, 2048)
		bg.texture = at
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.modulate = Color(0.45, 0.4, 0.35)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(false, 40))
	box.position = Vector2(120, 34)
	box.custom_minimum_size = Vector2(1680, 1010)
	box.size = Vector2(1680, 1010)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var t := UI.title("Le regole di Village", 48)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	for spec in [["Gioco base", _base_text], ["Locanda", _inn_text], ["Porto", _port_text], ["Obiettivi di vita", _goals_text]]:
		var b := UI.button(spec[0], 0, 50, 21)
		b.custom_minimum_size.x = 150
		var f: Callable = spec[1]
		b.pressed.connect(func():
			text.text = f.call()
			text.scroll_to_line(0)
			_paint(b))
		hb.add_child(b)
		tabs.append(b)
	var close := UI.primary(UI.button("Chiudi" if embedded else "Indietro", 170, 50, 22))
	close.pressed.connect(func():
		if embedded:
			on_close.call()
		else:
			main.show_menu())
	hb.add_child(close)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(1600, 890)
	text.add_theme_font_size_override("normal_font_size", 22)
	text.add_theme_font_size_override("bold_font_size", 21)
	vb.add_child(text)
	text.text = _base_text()
	_paint(tabs[0])


func _paint(sel: Button) -> void:
	for b in tabs:
		if b == sel:
			UI.selected(b, "meadow")
		else:
			UI.plain(b)


func _base_text() -> String:
	return (H % "Scopo") + """
Ogni giocatore guida una famiglia del villaggio attraverso le generazioni. I familiari lavorano nei campi, nelle botteghe, in chiesa, nella Camera di Consiglio o viaggiano; prima o poi il tempo li porta via, e chi ha vissuto bene entra nelle [b]cronache del villaggio[/b]. Vince chi ha più [b]punti prestigio[/b].

""" + (H % "Il round") + """
All'inizio di ogni round nel sacchetto verde si mettono i cubi indicati dalla carta preparazione e [b]tutti i cubi peste[/b]; poi si distribuiscono a caso i cubi sugli spazi azione. A turno, dal primo giocatore in senso orario, si [b]prende un cubo[/b] da uno spazio e si può fare l'azione di quello spazio. Il cubo influenza va nella fattoria; un [b]cubo peste[/b] fa perdere subito 2 tempi. Quando l'ultimo cubo è preso il round finisce con la [b]messa[/b].
[b]Pozzo[/b]: invece di prendere un cubo puoi restituire 3 cubi dello stesso colore e fare un'azione qualsiasi (solo finché c'è almeno un cubo sul tabellone).
[b]Monete[/b]: valgono come jolly al posto di un cubo influenza qualsiasi, comprano punti al 4° livello del Consiglio e i familiari alla messa; a fine partita 1 punto ciascuna.

""" + (H % "Il tempo e la morte") + """
Molte azioni costano tempo: il segnatempo avanza sulle nuvole della fattoria. Ogni volta che [b]passa il ponte[/b], alla fine del tuo turno muore il tuo familiare visibile con il numero più basso (a parità scegli tu; nel giorno di mercato si sceglie subito). Va nella sezione delle cronache del luogo dove lavorava (Consiglio, artigiani, viaggio, chiesa, fattoria); se quella sezione è piena va in una [b]tomba anonima[/b], senza punti. I familiari nel sacchetto nero e quelli non nati non muoiono.

""" + (H % "Le azioni") + """
[b]Mietitura[/b]: con almeno un familiare in fattoria prendi 2 grano, 3 con cavallo e aratro, 4 con bue e aratro (le merci restano). Al massimo 5 grano.
[b]Famiglia[/b]: nasce il familiare con il numero più basso disponibile, oppure riporti a casa un familiare dal tabellone.
[b]Artigiani[/b]: Fucina (aratro), Carradore (carro), Stalle (cavallo o bue), Ufficio (pergamena). Puoi addestrare un familiare dalla fattoria (tempo indicato) e produrre pagando altro tempo; chi è già a bottega produce pagando solo il tempo di produzione. Oppure compri la merce con i cubi (o il grano alle Stalle) senza nessun familiare. Fucina 3+3 tempi o arancione+rosa; Carradore 2+2 o arancione+rosa; Stalle 3+3 o 3 grano; Ufficio 2+2 o rosa. [b]Mulino[/b]: 2 tempi e 2 grano per 2 monete.
[b]Mercato[/b]: si apre un giorno di mercato (obbligatorio). Chi lo apre serve per primo, gratis; poi a turno ognuno può servire un cliente davanti alle bancarelle pagando le merci richieste più 1 cubo verde e 1 tempo, oppure passare per tutto il giorno. Alla fine i clienti in coda avanzano. Ogni cliente vale i punti stampati a fine partita.
[b]Viaggio[/b]: un familiare dalla fattoria va in una delle due città vicine al villaggio, oppure un viaggiatore si sposta in una città vicina. Costa 2 tempi, 1 carro e i cubi stampati sulla strada. Su ogni città nuova metti un segnalino e prendi il premio (3 punti, 1 moneta o 2 cubi a scelta).
[b]Camera di Consiglio[/b]: porti un familiare al 1° livello (1 tempo e 2 verdi o 1 pergamena) o lo fai salire di un livello (2, 2 o 3 tempi e 2 verdi o 1 pergamena), oppure usi solo un privilegio. Privilegi: 1° il segnalino del prossimo primo giocatore, 2° due cubi a scelta, 3° una merce a scelta, 4° paghi 1 moneta per 3 punti. Si può sempre scegliere un privilegio di livello più basso.
[b]Chiesa[/b]: un familiare della fattoria va nel sacchetto nero (1 marrone o 3 tempi).

""" + (H % "La messa") + """
1. Dal primo giocatore, ognuno può comprare i propri familiari nel sacchetto nero (1 moneta ciascuno) fino a 4 in tutto; il resto si estrae a caso insieme ai 4 frati. I familiari estratti vanno sulla vetrata più a destra.
2. Dal primo giocatore, ognuno una volta fa salire i suoi familiari verso sinistra pagando grano (1, 2 e 4 tra le vetrate).
3. Chi ha più familiari in chiesa prende 2 punti (a parità chi è più a sinistra; se resta pari, tutti).

""" + (H % "Fine della partita") + """
Quando un familiare occupa l'[b]ultimo spazio delle cronache[/b] o l'[b]ultima tomba anonima[/b], chi l'ha messo non gioca più; ogni altro fa un'ultima azione (se il tabellone è vuoto, l'azione è gratuita). Poi la messa finale e il punteggio:
[b]Viaggi[/b]: città visitate 1/2/3/4/5/6 = 1/3/6/10/14/18 punti. [b]Consiglio[/b]: 2/4/6 punti per familiare al 2°/3°/4° livello. [b]Chiesa[/b]: 2/3/4/6 punti per vetrata da destra. [b]Cronache[/b]: 3 familiari 4 punti, 4 = 7, 5 o più = 12. [b]Clienti[/b] e [b]monete[/b].
Spareggio: più clienti serviti, poi più familiari vivi.
Con meno di 4 giocatori alcuni spazi delle cronache, delle tombe e del mercato restano coperti; in 5 si usano le cronache e le tombe grandi.
"""


func _inn_text() -> String:
	return (H % "Village Inn · la Locanda") + """
Si aggiungono il [b]Birrificio[/b], la [b]Locanda[/b] (con il suo spazio azione turchese), 4 clienti che vogliono birra, le cronache e le tombe grandi e il quinto colore. Ognuno parte con 1 birra.

[b]Birrificio[/b] (azione Artigiani): produce sempre [b]2 birre[/b]: 3 tempi dopo aver addestrato un familiare (3 tempi), oppure 3 grano.
[b]Locanda[/b]: serve un tuo familiare alla Locanda (se non c'è, paghi 1 tempo e lo mandi dalla fattoria). Poi: 1. paghi 1 tempo; 2. mandi in fondo la carta in cima a uno dei 3 mazzi degli abitanti; 3. puoi accogliere l'abitante in cima a uno dei mazzi pagando il suo costo (1 moneta, 1 birra o 2 birre).
Chi muore alla Locanda finisce in una tomba anonima: gli ubriaconi non entrano nelle cronache!

""" + (H % "Gli abitanti") + """
Ogni abitante ha un effetto unico e si usa una volta. Quelli con la [b]candela spenta[/b] si tengono e contano nel punteggio finale (Sindaco, Suora, Maestro di gilda, Erudito, Artista, Conte, Viaggiatore, Medico, Contadina, Economo, Borsaiola). Gli altri si giocano: quelli "quando vuoi" durante il tuo turno (prima o dopo l'azione), gli altri nel loro momento (Vecchio saggio al posto di prendere un cubo, Giocoliere dopo l'azione, Imbonitore e Rigattiere al mercato, Prete alla messa, Gabelliere in viaggio, Mugnaio al mulino, Bardo quando muore un familiare).
Passa il mouse sulle carte per leggerne l'effetto completo.

In questa versione digitale le carte "quando vuoi" si giocano nel proprio turno (prima di scegliere il cubo o a fine turno).
"""


func _port_text() -> String:
	return (H % "Village Port · il Porto") + """
Il viaggio per terra è sostituito dal [b]mare[/b]: ogni famiglia ha una nave e una plancia con 3 stive. I segnalini dei viaggi non si usano e alla fine non si contano le città.

[b]Azione Viaggio[/b] (spazio verde):
a) [b]Salpare dal porto[/b]: ingaggi un capitano (1, 2 o 3 monete) — senza capitano non si parte —, carichi fino a 3 pezzi [b]di tipo diverso[/b] (cavallo, bue, aratro, carro, pergamena, grano, un familiare dalla fattoria) e muovi.
b) [b]Continuare dal mare[/b], con lo stesso capitano.
c) [b]Rientrare in porto[/b] da qualsiasi punto: 1 tempo, scarichi tutto e il capitano esce dal gioco.
Il [b]primo passo è gratis[/b]; gli altri si pagano con i cubi indicati dal capitano (da 1 moneta: arancione+rosa per passo; da 2: un cubo del suo colore per passo, o 2 cubi qualsiasi; da 3: un cubo per 2 passi, o 2 cubi qualsiasi per 2 passi). Ogni [b]acqua del tempo[/b] in cui entri costa 1 tempo.
Quando entri in un'isola puoi [b]approdare[/b]: il movimento finisce e puoi vendere le merci della stiva per i punti indicati, caricare la tessera in cima alla pila (cacao, tè o forziere) e fondare una [b]chiesa missionaria[/b] con un familiare della stiva pagando il costo indicato (carro dalla stiva e cubi): prendi subito i punti.
Il [b]forziere[/b] vale 3, 4 o 5 monete: in questa versione si apre appena la nave rientra.
[b]Mercato[/b]: nel tuo turno di vendita puoi anche vendere 1 cacao (7 punti) o 1 tè (5 punti e 1 moneta) portati a casa.
[b]Morte in mare[/b]: chi muore sulla nave o in una missione va nelle cronache dei viaggi; se sono piene viene sepolto in mare (2, 1, 0 punti). La partita finisce anche quando si occupa l'ultima sepoltura in mare.
Con la Locanda: Conte, Viaggiatore, Messaggero e Gabelliere lasciano il posto ad Ammiraglio, Timoniere, Quartiermastro e Cartografo.
"""


func _goals_text() -> String:
	var t := (H % "Obiettivi di vita") + """
Ogni famiglia riceve in segreto un obiettivo d'[b]argento[/b] (5 punti) e uno d'[b]oro[/b] (8 punti). Appena ne soddisfi i requisiti l'obiettivo si rivela e incassi i punti (non devi cedere nulla). Non c'è penalità se non li completi. Alcuni obiettivi si tolgono a seconda delle espansioni in gioco.

[b]Argento[/b]
"""
	for i in VLData.GOALS_SILVER.size():
		t += "· " + Describe.goal_text(["s", i]) + "\n"
	t += "\n[b]Oro[/b]\n"
	for i in VLData.GOALS_GOLD.size():
		t += "· " + Describe.goal_text(["g", i]) + "\n"
	return t
