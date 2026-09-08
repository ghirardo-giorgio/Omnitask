# Omnitask — la dashboard quickshell sul telefono

App Android che mostra le sezioni della dashboard
[quickshell](../../quickshell) su un telefono: le stesse metriche, gli stessi
grafici, gli stessi colori, aggiornate ogni due secondi finché si guardano.

Il campionamento resta sul PC. L'app non legge niente della macchina: si
collega al ponte (`scripts/phone_bridge.py` nel repository della dashboard) e
riceve quello che ha chiesto.

---

## Primo avvio

Serve il ponte già in esecuzione sul PC, sulla stessa rete WiFi. Alla prima
apertura vanno inseriti:

| Campo | Valore |
| --- | --- |
| Indirizzo del PC | es. `192.168.1.50` |
| Porta | `8770` (default del ponte) |
| Token | 5 cifre, generate dal ponte al primo avvio |

Il token sta in `~/.config/quickshell/phone-bridge.json` sul PC, ed è stampato
nel log del ponte quando parte la prima volta:

```bash
python3 scripts/phone_bridge.py --token
```

**Verifica connessione** prova indirizzo, porta e token senza salvare niente:
un token sbagliato salvato costringerebbe a tornare qui dopo aver guardato una
schermata che gira a vuoto.

Da lì in poi l'app si ricollega da sola all'avvio e dopo ogni caduta,
riprovando ogni tre secondi. Lo schermo resta acceso finché l'app è in primo
piano — è una dashboard, si guarda.

---

## La vista dinamica

La prima pagina, quella più a sinistra, non la riempie l'utente: ci finisce da solo quello che
in questo momento merita attenzione. Se la CPU schizza compare la CPU, e sotto la classifica
di chi la sta usando; se un disco è dato per spacciato da SMART compare quello, anche se non
sta facendo niente.

**Carico e guai stanno nella stessa scala** perché la domanda a cui la vista risponde — cosa
guardo adesso — ha una risposta sola. Un disco in avaria non sta lavorando affatto ed è la
cosa più urgente che ci sia; una CPU al 90% mentre si compila è esattamente ciò che dovrebbe
succedere.

I punteggi li calcola il PC, che è l'unico ad avere sotto mano i dati di tutti i moduli anche
quando il telefono ne sta scaricando due. Le soglie invece stanno qui: un punteggio è un fatto
della macchina, la soglia oltre la quale «merita attenzione» è una preferenza di chi guarda.

Tre regole la rendono guardabile invece che epilettica, e si toccano dalla schermata delle
soglie (l'icona del tachimetro):

- si entra alla soglia (80 di partenza) e si esce dieci punti più in basso, altrimenti un
  modulo che oscilla intorno al valore di taglio entrerebbe e uscirebbe a ogni campione;
- chi è entrato resta almeno venti secondi anche se crolla subito: una card che compare e
  sparisce a ogni picco è peggio che non mostrarla;
- l'ordine è per urgenza, così il primo che si vede è il più grave.

**La lista delle soglie è anche la lista delle priorità**: si trascina per maniglia e l'ordine
che ne esce è la tua preferenza. Non scavalca l'urgenza — un disco in avaria resta in cima
anche se è l'ultimo della lista — ma decide fra moduli grosso modo pari merito, che è poi il
caso frequente: quando dieci cose sono tutte sopra soglia i punteggi si somigliano, e senza
una preferenza l'ordine della prima pagina lo deciderebbero decimali che cambiano a ogni
campione. «Grosso modo pari merito» vuol dire dentro la stessa fascia di dieci punti: 95 e 91
sono la stessa cosa, 95 e 82 no.

**Quando la macchina è tranquilla** la vista non si svuota: mostra i tre col punteggio più
alto e lo dichiara in cima, «tutto tranquillo». Una schermata vuota sembra rotta, e a riposo è
proprio quando la si apre per controllare che sia tutto a posto.

**Quando i moduli attivi sono più di quanti ne stiano in una schermata** le pagine ruotano da
sole ogni otto secondi. Al primo tocco — anche solo l'inizio di uno scorrimento — la rotazione
si ferma e riprende dopo trenta secondi di quiete: senza la pausa si sta leggendo una riga e
la pagina scappa. I puntini in cima dicono a che pagina si è e si toccano per andarci; accanto
c'è l'indicazione di rotazione o di pausa, così si capisce perché la pagina si muove.

**Un modulo può essere escluso dalla sola vista dinamica** con l'interruttore ambra nella
lista delle soglie: resta acceso nella sua sezione e lo si guarda quando lo si vuole guardare,
ma non viene mai a chiamare. Serve per le cose che stanno in alto per natura senza che sia una
notizia — una rete che scarica di continuo, un disco tenuto pieno per scelta — dove spegnere
il modulo sarebbe troppo e alzare la soglia a cento è un modo obliquo di dire la stessa cosa.
Escluderlo lo fa uscire subito, senza aspettare i venti secondi di permanenza: quelli servono
contro i capricci dei punteggi, non contro una decisione presa.

Un modulo spento del tutto dall'elenco dei moduli, invece, non entra nella vista per quanto
alto sia il suo punteggio: spegnere una cosa deve toglierla da tutto, non farla ricomparire
proprio quando è in attività. E i moduli senza un'urgenza sensata — Home Assistant nel suo insieme, il meteo —
non entrano mai: sono cose che si consultano, non che chiamano.

La vista si spegne dall'interruttore in cima alla schermata delle soglie, e allora l'app parte
dalle sezioni fisse come prima.

---

## Sezioni

Una pagina per sezione, si passa con lo swipe orizzontale; i puntini in basso
dicono a che pagina si è. Dentro, i moduli accesi uno sotto l'altro.

Le sezioni sono il motivo per cui questa app non è la dashboard rimpicciolita.
Uno schermo di telefono tiene un sesto di quello che tiene lo schermo del PC,
quindi invece di mostrare tutto in piccolo si mostra poco alla volta — e
quello che non si guarda **non viene nemmeno chiesto al PC**: aprire la
sezione Rete fa interrogare le connessioni sul PC, uscirne lo fa smettere
entro un giro.

Il pulsante in alto a sinistra apre l'elenco: interruttore per accendere e
spegnere, maniglia per riordinare, e in fondo i moduli spenti. Si creano
quante sezioni si vuole. Non c'è nessun pulsante «Applica»: ogni modifica va
su disco subito, come nelle opzioni della dashboard.

Le sezioni di partenza sono la traduzione delle tre colonne del desktop in
qualcosa che stia in uno schermo alto e stretto:

| Sezione | Moduli |
| --- | --- |
| Sistema | CPU, RAM, GPU, VRAM, consumo, frequenza e le tre classifiche |
| Salute | temperature, dischi con SMART, stato del sistema, pressione |
| Rete | traffico con grafico, e chi sta parlando con chi |
| Casa | Home Assistant, solare, igrometro, meteo |
| Persona | battito, Inspire 3 |
| Dispositivi | telefoni via KDE Connect |

Gli id dei moduli sono gli stessi dei pannelli del desktop (`cpu`, `topram`,
`net`, `heart`…), così una configurazione si legge da tutte e due le parti.

---

## I grafici

Rifatti con `CustomPainter` invece che con una libreria, per assomigliare a
quelli del desktop e non a quelli di qualcun altro: linea più area sfumata, i
valori recenti a destra, nessun autoscale dove il desktop non ce l'ha.

Due dettagli che sembrano capricci e non lo sono:

- **L'ancoraggio a destra.** La larghezza di un campione si calcola su quanti
  ne entrano in tutto, non su quanti ce ne sono adesso: una serie appena nata
  resta incollata al bordo destro e cresce verso sinistra, invece di
  allargarsi come una fisarmonica mentre si riempie.
- **I buchi restano buchi.** Un `null` spezza la linea invece di valere zero.
  Il battito arriva un punto al minuto e manca dove il braccialetto era sul
  comodino: uno zero al suo posto disegnerebbe un arresto cardiaco.

Il fondoscala e il colore di ogni serie arrivano col dato. Il colore è quello
scelto sul desktop col menu del tasto destro, così una serie è dello stesso
colore su tutti e due gli schermi senza che la tavolozza sia scritta due
volte.

---

## Sicurezza

Rete locale soltanto. Il canale è cifrato quando il ponte ha un certificato —
e se lo genera da solo al primo avvio: l'app lo fissa al primo collegamento e
da lì in poi ne rifiuta uno diverso, mostrando le due impronte a confronto.
Se il certificato cambia davvero (ponte reinstallato) si accetta con un tocco;
altrimenti c'è qualcuno sulla rete che si spaccia per il PC, e le due cose da
qui non si distinguono.

Il token è di cinque cifre perché si digita su un telefono senza sbagliare.
È corto, ed è per questo che il ponte ha sopra un limite di cinque tentativi
al minuto per indirizzo e sotto il TLS.

L'app non manda niente a nessun servizio esterno, e tutto quello che riceve è
in sola lettura: non c'è nessun comando che cambi qualcosa sul PC.

---

## Struttura

```
lib/
  models/     connection_settings · snapshot (le sorgenti e le serie) · module_spec
              activity (punteggi e regole della vista dinamica)
  services/   bridge_client (TCP+TLS, riconnessione) · settings_service (sezioni)
              activity_monitor (chi entra, chi resta, chi esce, e a che pagina)
  theme/      app_colors (la tavolozza del desktop) · app_metrics
  widgets/    sparkline · module_card, StatBar, ValueRow · format · dynamic_view
  modules/    system · health · network · home · body · devices · registry
  screens/    connection · dashboard · sections · activity_settings
  l10n/       strings (la chiave è la stringa italiana, come sul desktop)
```

Il catalogo dei moduli è `modules/registry.dart`. Sul desktop non esiste — lo
compone `scripts/panels.py` leggendo la cartella `panels/` — ma in un'app
compilata non c'è nessuna cartella da scandire, quindi è una mappa.
Aggiungere un modulo vuol dire scrivere la funzione che lo disegna e una voce
lì dentro, con le serie che gli servono; alla sottoscrizione ci pensa la
dashboard da sola.

---

## Sviluppo

```bash
flutter test                      # la logica, e la catena intera se il ponte è acceso
flutter run -d <telefono>
flutter build apk --release
```

`test/live_bridge_test.dart` prova app → TLS → ponte → `qs ipc` → dashboard
contro un ponte vero, e si salta da solo se non ne trova uno in ascolto. Uno dei
suoi casi carica davvero tutti i thread della macchina e verifica che la CPU
entri nella vista dinamica e ci resti per la permanenza minima.

`test/activity_monitor_test.dart` prova le tre regole delicate senza rete e
senza aspettare: l'orologio è finto, così i venti secondi di permanenza passano
in un'istruzione.
