#!/usr/bin/env python3
"""Installa Omnitask sull'iPhone con xtool, senza doversi ricordare il Ctrl-C.

    ./tools/install_ios.py            scarica l'ultimo IPA dalle Actions e installa
    ./tools/install_ios.py --local    usa l'IPA gia' presente
    ./tools/install_ios.py --run      installa e avvia l'app

Due cose che questo script fa e che a mano si dimenticano.

**Alloca uno pseudo-terminale.** xtool prende possesso di stdin e stdout con
`NIOPipeBootstrap.takingOwnershipOfDescriptors` per scriverci i propri prompt --
il codice 2FA, la conferma di revocare un certificato. Senza un tty vero quel
canale muore con `epoll_ctl ... EPERM` e xtool crasha a "Provisioning 33%": un
errore che sembra ambientale e invece e' una domanda che non e' riuscita ad
arrivare. Con un pty il prompt si vede e si puo' rispondere, e questo script
inoltra quello che scrivi.

**Lo interrompe quando ha finito.** `xtool install` non esce da solo: porta
tutte le sue fasi al 100%, poi resta li'. "Successfully installed!" compare solo
alla chiusura, il che dice dove sta: nel percorso di uscita, cioe' oltre
l'installazione, che era gia' finita. Qui si aspetta l'ultima fase e si manda lo
stesso SIGINT che manderebbe un Ctrl-C.
"""

import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
import tty
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IPA = os.environ.get("IPA", "Omnitask.ipa")
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.shinrisama.omnitask")
ARTIFACT = os.environ.get("ARTIFACT", "Omnitask-ipa")

# Quanto si aspetta in tutto se l'ultima fase non arriva mai: un'installazione
# riuscita ci mette meno di un minuto, ma una che deve chiedere il 2FA aspetta
# una persona.
DEADLINE = int(os.environ.get("DEADLINE", "600"))
# Quanto si lascia respirare xtool dopo l'ultima fase, prima di interromperlo.
GRACE = float(os.environ.get("GRACE", "4"))

DONE = re.compile(r"\[Installing\][^\n]*100%")


def log(message):
    print("\033[1;34m==>\033[0m %s" % message, flush=True)


def warn(message):
    print("\033[1;33m[!]\033[0m %s" % message, file=sys.stderr, flush=True)


def die(message):
    print("\033[1;31m[x]\033[0m %s" % message, file=sys.stderr, flush=True)
    raise SystemExit(1)


def run(args, **kwargs):
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def devices():
    found = run(["xtool", "devices"])
    return [line for line in found.stdout.splitlines() if line.strip()]


def describe(path):
    """Bundle id e versione di un ipa, per accorgersi di star installando
    l'app sbagliata prima e non dopo."""
    try:
        import plistlib

        with zipfile.ZipFile(path) as ipa:
            name = next(n for n in ipa.namelist() if n.endswith(".app/Info.plist"))
            info = plistlib.loads(ipa.read(name))
        return "%s %s" % (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"))
    except Exception:
        return "?"


def download():
    if not run(["command", "-v", "gh"]).returncode == 0 and not _has("gh"):
        die("gh non e' installato: usa --local con un ipa gia' scaricato")
    log("Scarico l'ipa dall'ultima build")
    if os.path.exists(IPA):
        os.unlink(IPA)
    done = run(["gh", "run", "download", "--name", ARTIFACT])
    if done.returncode != 0 or not os.path.exists(IPA):
        die("nessun artefatto da scaricare (la build e' passata? `gh run list`)")


def _has(binary):
    return any(
        os.access(os.path.join(directory, binary), os.X_OK)
        for directory in os.environ.get("PATH", "").split(os.pathsep)
        if directory
    )


def install():
    """xtool sotto pty. Ritorna True se l'installazione e' arrivata in fondo."""
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        ["xtool", "install", IPA],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)

    # Il terminale di chi guarda passa in raw, cosi' una risposta a un prompt
    # arriva carattere per carattere invece che a fine riga. Se non c'e' un
    # terminale (lo script gira dentro un altro strumento) si salta: il pty di
    # xtool resta comunque, ed e' quello che conta.
    interactive = sys.stdin.isatty()
    saved = None
    if interactive:
        saved = termios.tcgetattr(sys.stdin)
        tty.setraw(sys.stdin.fileno())

    transcript = []
    finished_at = None
    started = time.monotonic()

    try:
        while True:
            if proc.poll() is not None:
                break

            watching = [master] + ([sys.stdin] if interactive else [])
            ready, _, _ = select.select(watching, [], [], 0.5)

            if master in ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                text = chunk.decode("utf-8", "replace")
                transcript.append(text)
                sys.stdout.write(text)
                sys.stdout.flush()

            if interactive and sys.stdin in ready:
                typed = os.read(sys.stdin.fileno(), 1024)
                if typed:
                    os.write(master, typed)

            whole = "".join(transcript)

            if finished_at is None and DONE.search(whole):
                finished_at = time.monotonic()
            elif finished_at is not None and time.monotonic() - finished_at >= GRACE:
                proc.send_signal(signal.SIGINT)
                try:
                    proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    proc.terminate()
                break

            if time.monotonic() - started > DEADLINE:
                warn("scaduti %d secondi senza vedere la fine dell'installazione" % DEADLINE)
                proc.send_signal(signal.SIGINT)
                break
    finally:
        if saved is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, saved)
        os.close(master)
        # Un ultimo respiro per il messaggio di chiusura, che xtool stampa
        # dopo il SIGINT.
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    whole = "".join(transcript)
    print(flush=True)
    if "successfully installed" in whole.lower():
        return True
    if DONE.search(whole):
        log("xtool non l'ha detto, ma l'ultima fase e' arrivata al 100%")
        return True
    warn("non sembra completata; ultime righe:")
    print("\n".join(whole.splitlines()[-8:]), file=sys.stderr)
    return False


def main():
    os.chdir(ROOT)
    args = sys.argv[1:]
    unknown = [a for a in args if a not in ("--local", "--run")]
    if unknown:
        die("opzione sconosciuta: %s" % " ".join(unknown))

    if not _has("xtool"):
        die("xtool non e' nel PATH")

    if run(["systemctl", "is-active", "usbmuxd"]).stdout.strip() != "active":
        warn("usbmuxd non e' attivo: senza, l'iPhone non si vede")
        warn("  sudo systemctl start usbmuxd")

    connected = devices()
    if not connected:
        die("nessun iPhone collegato (sbloccalo e autorizza il computer)")
    log(connected[0])

    if "--local" not in args:
        download()
    if not os.path.exists(IPA):
        die("%s non c'e'" % IPA)

    size = os.path.getsize(IPA) / (1024 * 1024)
    log("%s — %.1f MB, %s" % (IPA, size, describe(IPA)))
    log("Installo (da qui in giu' parla xtool)")

    if not install():
        return 1

    log("Installata.")
    print("    Al primo avvio: Impostazioni > Generali > VPN e gestione dispositivo > autorizza.")

    if "--run" in args:
        log("Avvio %s" % BUNDLE_ID)
        subprocess.run(["xtool", "launch", BUNDLE_ID])
    return 0


if __name__ == "__main__":
    sys.exit(main())
