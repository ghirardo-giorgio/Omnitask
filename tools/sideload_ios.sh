#!/usr/bin/env bash
# Firma e installa l'IPA sull'iPhone dal PC Linux, con Apple ID gratuito.
# La VM macOS compila (tools/deploy_ios.sh --ipa), questo script installa.
#
# Backend di firma (BACKEND=sideloader|altserver, default sideloader):
#   sideloader  Dadoum/Sideloader, gestisce l'anisette da solo
#   altserver   AltServer-Linux + anisette server in Docker
# Diagnosi rapida dell'account:  tools/sideload_ios.sh --teams
# Prerequisiti a carico tuo: iPhone staccato dal passthrough USB della VM,
# collegato a questo PC, sbloccato e con "Autorizza questo computer" accettato.
set -euo pipefail

IPA="${IPA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/Omnitask-unsigned.ipa}"
ANISETTE="${ANISETTE:-http://localhost:6969}"
ALTSERVER="${ALTSERVER:-$HOME/.local/bin/AltServer}"
SIDELOADER="${SIDELOADER:-$HOME/.local/bin/sideloader}"
BACKEND="${BACKEND:-sideloader}"
[ "${1:-}" = "--teams" ] && LIST_TEAMS=1 || LIST_TEAMS=0

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$IPA" ] || die "IPA non trovato: $IPA  (generalo con ./tools/deploy_ios.sh --ipa)"
if [ "$BACKEND" = "altserver" ]; then
  [ -x "$ALTSERVER" ] || die "AltServer non trovato in $ALTSERVER"
else
  [ -x "$SIDELOADER" ] || die "Sideloader non trovato in $SIDELOADER"
fi

# --- anisette: serve solo ad AltServer (Sideloader se lo gestisce da solo) ---
if [ "$BACKEND" = "altserver" ]; then
if ! curl -s --max-time 5 "$ANISETTE" | grep -q "X-Apple-I-MD"; then
  log "Avvio l'anisette server"
  docker start anisette >/dev/null 2>&1 || \
    docker run -d --name anisette --restart unless-stopped -p 6969:6969 \
      -v anisette-data:/home/Alcoholic/.config/anisette-v3/lib/ dadoum/anisette-v3-server >/dev/null
  for _ in $(seq 1 15); do
    curl -s --max-time 3 "$ANISETTE" | grep -q "X-Apple-I-MD" && break
    sleep 1
  done
fi
curl -s --max-time 5 "$ANISETTE" | grep -q "X-Apple-I-MD" || die "anisette server non risponde su $ANISETTE"
log "anisette server attivo"
fi

# --- usbmuxd (sull'host e' mascherato per lasciare l'USB alla VM) -----------
if ! systemctl is-active --quiet usbmuxd; then
  warn "usbmuxd non e' attivo. Lancia in un altro terminale:"
  echo "    sudo systemctl unmask usbmuxd && sudo systemctl start usbmuxd"
  echo "  (per ridare l'iPhone alla VM in futuro: sudo systemctl stop usbmuxd && sudo systemctl mask usbmuxd)"
  die "riprova quando usbmuxd e' attivo"
fi

UDID="$(idevice_id -l 2>/dev/null | head -1 || true)"
[ -n "$UDID" ] || die "Nessun iPhone visto da questo PC. Staccalo dal passthrough USB della VM, collegalo qui, sbloccalo e accetta 'Autorizza'."
log "iPhone rilevato: $UDID"

# --- diagnosi account: elenca i team di sviluppo ----------------------------
if [ "$LIST_TEAMS" = 1 ]; then
  log "Interrogo Apple per i team di sviluppo dell'account"
  exec "$SIDELOADER" team list -i
fi

warn "Le credenziali restano su questo terminale. Se hai la 2FA, tieni pronto il codice a 6 cifre."
if [ "$BACKEND" = "altserver" ]; then
  # Apple risponde spesso 503 alla prima richiesta dopo la verifica 2FA: la sessione
  # e' appena nata e il tentativo successivo puo' passare.
  read -rp "Apple ID: " APPLE_ID
  read -rsp "Password Apple ID: " APPLE_PW; echo
  ATTEMPTS="${ATTEMPTS:-3}"
  for i in $(seq 1 "$ATTEMPTS"); do
    log "Firmo e installo $(basename "$IPA") (AltServer, tentativo $i/$ATTEMPTS)"
    ALTSERVER_ANISETTE_SERVER="$ANISETTE" "$ALTSERVER" -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" "$IPA" 2>&1 \
      | tee /tmp/altserver-$$.log | grep -vE "^Byte:"
    grep -q "Installation Succeeded" /tmp/altserver-$$.log && { rm -f /tmp/altserver-$$.log; break; }
    [ "$i" -lt "$ATTEMPTS" ] && { warn "Fallito, riprovo tra 10s..."; sleep 10; } \
                             || { rm -f /tmp/altserver-$$.log; die "Apple rifiuta la richiesta dopo $ATTEMPTS tentativi."; }
  done
else
  # Sideloader chiede le credenziali da solo (-i) e le conserva per le volte successive.
  log "Firmo e installo $(basename "$IPA") con Sideloader"
  "$SIDELOADER" install -i --udid "$UDID" "$IPA"
fi

log "Fatto. Sull'iPhone: Impostazioni > Generali > VPN e gestione dispositivo > autorizza lo sviluppatore."
warn "Con Apple ID gratuito la firma scade dopo 7 giorni: rilancia questo script per rinnovarla."
