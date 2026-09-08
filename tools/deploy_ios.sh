#!/usr/bin/env bash
# Pipeline: copia il progetto sulla VM macOS, lo compila e lo installa sull'iPhone.
#
#   ./tools/deploy_ios.sh              build release + install sull'iPhone
#   ./tools/deploy_ios.sh --debug      build debug (firma piu' permissiva)
#   ./tools/deploy_ios.sh --no-install solo compilazione, nessuna installazione
#   ./tools/deploy_ios.sh --check      solo verifica ambiente remoto
#   ./tools/deploy_ios.sh --ipa        produce un .ipa non firmato e lo scarica in locale
#                                      (da firmare altrove, es. Sideloadly/AltServer)
#   ./tools/deploy_ios.sh --clean      pulisce la copia remota prima di ricostruire
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-macos}"
REMOTE_DIR="${REMOTE_DIR:-Projects/omnitask}"          # relativo alla home remota
BUNDLE_ORG="${BUNDLE_ORG:-com.shinrisama}"             # bundle id -> com.shinrisama.omnitask
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="release"
DO_INSTALL=1
DO_CLEAN=0
CHECK_ONLY=0
MAKE_IPA=0
for arg in "$@"; do
  case "$arg" in
    --debug)      MODE="debug" ;;
    --release)    MODE="release" ;;
    --no-install) DO_INSTALL=0 ;;
    --clean)      DO_CLEAN=1 ;;
    --check)      CHECK_ONLY=1 ;;
    --ipa)        MAKE_IPA=1; DO_INSTALL=0 ;;
    *) echo "Opzione sconosciuta: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# PATH remoto: Flutter, Homebrew (CocoaPods) e Xcode non sono nel PATH di una shell ssh non interattiva.
REMOTE_ENV='export PATH="$HOME/development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; export LANG=en_US.UTF-8;'
rsh() { ssh "$REMOTE_HOST" "$REMOTE_ENV $*"; }

# --- 1. verifica ambiente remoto -------------------------------------------
log "Verifico l'ambiente su $REMOTE_HOST"
rsh 'command -v flutter >/dev/null' || die "Flutter non trovato sulla VM"
rsh 'command -v pod >/dev/null'     || die "CocoaPods non trovato sulla VM (brew install cocoapods)"
rsh 'xcode-select -p >/dev/null'    || die "Xcode non configurato sulla VM"

DEVICE_ID="$(rsh 'flutter devices --machine' \
  | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin) if x.get("targetPlatform","").startswith("ios") and not x.get("emulator")]; print(d[0]["id"] if d else "")')"
[ -n "$DEVICE_ID" ] || warn "Nessun iPhone fisico rilevato (sbloccalo e autorizza il Mac)"
[ -n "$DEVICE_ID" ] && log "iPhone rilevato: $DEVICE_ID"

echo "    firma: $(rsh 'security find-identity -v -p codesigning' | tail -1 | sed 's/^ *//')"

if [ "$CHECK_ONLY" = 1 ]; then
  rsh 'flutter doctor'
  exit 0
fi

# --- 2. copia del progetto --------------------------------------------------
[ "$DO_CLEAN" = 1 ] && { log "Pulisco la copia remota"; rsh "rm -rf '$REMOTE_DIR'"; }
log "Copio il progetto in $REMOTE_HOST:~/$REMOTE_DIR"
rsh "mkdir -p '$REMOTE_DIR'"
rsync -az --delete \
  --exclude '.git/' --exclude 'build/' --exclude '.dart_tool/' \
  --exclude 'android/' --exclude 'linux/' --exclude 'windows/' --exclude 'web/' \
  --exclude '.idea/' --exclude '*.iml' \
  --exclude 'ios/Pods/' --exclude 'ios/.symlinks/' --exclude 'ios/Flutter/Flutter.framework' \
  --exclude 'ios/Flutter/ephemeral/' \
  "$LOCAL_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

# --- 3. piattaforma iOS + dipendenze ---------------------------------------
if ! rsh "test -d '$REMOTE_DIR/ios'"; then
  log "Genero la piattaforma iOS (bundle id $BUNDLE_ORG.omnitask)"
  rsh "cd '$REMOTE_DIR' && flutter create --platforms=ios --org '$BUNDLE_ORG' ."
fi
log "flutter pub get"
rsh "cd '$REMOTE_DIR' && flutter pub get"

# --- 4. team di firma ---------------------------------------------------------
# Flutter legge il team dal progetto Xcode: se DEV_TEAM e' impostato lo scriviamo
# nel project.pbxproj remoto (firma automatica), altrimenti usiamo quello gia' presente.
# se DEV_TEAM non e' passato a mano, lo si ricava dagli account configurati in Xcode
if [ -z "${DEV_TEAM:-}" ]; then
  DEV_TEAM="$(rsh 'defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null' \
    | grep -o '"teamID" = "[A-Z0-9]*"' | head -1 | grep -o '[A-Z0-9]\{10\}' || true)"
  [ -n "$DEV_TEAM" ] && log "Team rilevato dagli account Xcode: $DEV_TEAM"
fi
CURRENT_TEAM="$(rsh "grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' '$REMOTE_DIR/ios/Runner.xcodeproj/project.pbxproj' | awk '{print \$3}'" || true)"
if [ -n "${DEV_TEAM:-}" ] && [ "${DEV_TEAM:-}" != "$CURRENT_TEAM" ]; then
  log "Imposto il team di sviluppo $DEV_TEAM nel progetto Xcode"
  rsh "cd '$REMOTE_DIR/ios' && python3 - <<'PY'
import re, pathlib
p = pathlib.Path('Runner.xcodeproj/project.pbxproj')
s = p.read_text()
s = re.sub(r'DEVELOPMENT_TEAM = [A-Z0-9]*;', 'DEVELOPMENT_TEAM = $DEV_TEAM;', s)
# aggiunge la chiave dove manca, subito dopo CODE_SIGN_STYLE
s = re.sub(r'(CODE_SIGN_STYLE = Automatic;)(?!\s*\n\s*DEVELOPMENT_TEAM)',
           r'\1\n\t\t\t\t\tDEVELOPMENT_TEAM = $DEV_TEAM;', s)
p.write_text(s)
PY"
elif [ -n "$CURRENT_TEAM" ]; then
  log "Team di sviluppo gia' configurato: $CURRENT_TEAM"
else
  warn "Nessun team di sviluppo configurato: compilo senza firma (.app non installabile)."
  warn "Aggiungi il tuo Apple ID in Xcode > Settings > Accounts, poi rilancia con DEV_TEAM=<TeamID>."
  NO_CODESIGN="--no-codesign"
fi

# --- 4b. build ---------------------------------------------------------------
log "Compilo ($MODE)"
rsh "cd '$REMOTE_DIR' && flutter build ios --$MODE ${NO_CODESIGN:-}"
# --- 4c. pacchetto .ipa (per firmare altrove) --------------------------------
if [ "$MAKE_IPA" = 1 ]; then
  log "Impacchetto Runner.app in un .ipa"
  rsh "cd '$REMOTE_DIR' && rm -rf build/ipa && mkdir -p build/ipa/Payload \
       && cp -R build/ios/iphoneos/Runner.app build/ipa/Payload/ \
       && cd build/ipa && zip -qry ../Omnitask${NO_CODESIGN:+-unsigned}.ipa Payload"
  mkdir -p "$LOCAL_DIR/build"
  rsync -a "$REMOTE_HOST:$REMOTE_DIR/build/Omnitask${NO_CODESIGN:+-unsigned}.ipa" "$LOCAL_DIR/build/"
  log "IPA scaricato in build/Omnitask${NO_CODESIGN:+-unsigned}.ipa"
fi

[ -n "${NO_CODESIGN:-}" ] && { warn "Build senza firma completata: installazione dalla VM non possibile."; exit 0; }

# --- 5. installazione sull'iPhone ------------------------------------------
if [ "$DO_INSTALL" = 1 ] && [ -n "$DEVICE_ID" ]; then
  log "Installo sull'iPhone $DEVICE_ID"
  rsh "cd '$REMOTE_DIR' && flutter install -d '$DEVICE_ID' --$MODE"
  log "Fatto. Se l'app non parte: Impostazioni > Generali > VPN e gestione dispositivo > autorizza lo sviluppatore."
elif [ "$DO_INSTALL" = 1 ]; then
  warn "Installazione saltata: nessun iPhone rilevato."
fi
