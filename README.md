# SborrSign

(nome interno del progetto: Forgia)

Installer di IPA che gira **sul telefono**. Importi un `.ipa` non firmato, lo firmi
con il tuo `.p12` + `.mobileprovision`, e lo installi — senza computer.

Stessa idea di ESign o Feather, ma scritto da zero e ridotto all'essenziale.

> Firma solo app che hai il diritto di installare. Il certificato e la sua
> password non lasciano mai il telefono.

---

## Com'è fatta

| pezzo | come |
|---|---|
| Firma | [zsign](https://github.com/zhlynn/zsign) nel port iOS di `Zsign-Package`, via SwiftPM (OpenSSL incluso) |
| Archivi | [Zip](https://github.com/marmelroy/Zip) per estrarre e ricompattare l'IPA |
| Installazione | server HTTP/HTTPS locale su Network.framework + `itms-services://` |
| Interfaccia | SwiftUI, iOS 17+ |

Il progetto Xcode non è versionato: lo genera **XcodeGen** da `project.yml`.

---

## Il nodo dell'installazione

iOS non lascia che un'app ne installi un'altra. L'unica strada senza jailbreak è
`itms-services://`: si passa a iOS l'indirizzo di un *manifest*, lui lo scarica e
poi scarica il pacchetto. Il vincolo è che **il manifest deve stare su HTTPS con un
certificato valido**, cosa che un server dentro il telefono non può avere
(nessuna CA pubblica emette certificati per `127.0.0.1`).

Il pacchetto, invece, iOS lo scarica anche in **HTTP**.

Da qui le due modalità, in Impostazioni:

**1. Manifest esterno** (predefinita, non richiede nulla)
Il pacchetto resta sul telefono e viene servito in chiaro su `127.0.0.1`; solo il
manifest — poche righe di XML con nome, bundle id e versione — viene generato da un
servizio HTTPS esterno. Serve internet. Il servizio è configurabile.

**2. Tutto in locale (HTTPS)**
Niente esce dal telefono, ma devi importare un certificato TLS per un nome host che
risolva a `127.0.0.1`. Due modi: un dominio tuo con un record A su `127.0.0.1` e un
certificato Let's Encrypt (DNS-01), oppure una CA tua installata sul telefono e
abilitata in *Impostazioni → Generali → Info → Impostazioni di attendibilità
certificati*.

> Fino a ottobre 2026 esisteva `*.backloop.dev`, che risolveva a `127.0.0.1` con un
> certificato di CA pubblica: è il trucco che usavano ESign e Feather. Il servizio è
> stato chiuso e il certificato revocato, quindi quella scorciatoia non c'è più.

**3. Ripiego che funziona sempre**
Da ogni app firmata puoi fare *Esporta l'IPA firmato*: il file è già firmato, lo
installi con Sideloadly, AltStore o Apple Configurator.

---

## Compilare l'IPA

Non serve un Mac: la build gira su GitHub Actions con i runner macOS.

1. Carica questa cartella in un repository GitHub.
2. **Actions** → `Build IPA (unsigned)`: parte da sola al push, oppure **Run workflow**.
3. A fine build scarica l'artifact **Forgia-unsigned-ipa**: dentro c'è `Forgia-unsigned.ipa`.

Con un Mac:

```bash
brew install xcodegen
xcodegen generate
open Forgia.xcodeproj        # Signing & Capabilities → il tuo team → Run
```

Poi firma `Forgia-unsigned.ipa` con lo stesso certificato che userai dentro l'app
(Sideloadly, AltStore, o Xcode) e installala.

Il bundle id è `com.dchietti.forgia`: cambialo in `project.yml` se ti serve.

---

## Usarla

**Certificati** → `+` → scegli il `.p12` e il `.mobileprovision`, metti la password.
L'app ti mostra team, tipo di profilo, quali bundle id copre, scadenza e UDID
autorizzati. La password finisce nel Keychain.

**Libreria** → `+` per importare un `.ipa`, oppure aprilo da File o da Safari con
*Apri in → Forgia*.

**Firma** → scegli il certificato. Se il profilo non è jolly devi cambiare il bundle
id in uno che il profilo copra: l'app te lo dice prima di provare.

**Installa** → iOS chiede conferma e scarica il pacchetto dal server locale. Tieni
Forgia aperta finché l'icona non compare: in background l'app resta viva con un
flusso audio muto, ma non chiuderla a mano.

---

## Se qualcosa non va

**"Impossibile installare"** — l'UDID del telefono non è nel profilo, oppure il
bundle id non rientra nell'App ID. Controlla la scheda del certificato.

**L'installazione non parte** — prova a spegnere *Usa 127.0.0.1* in Impostazioni:
il manifest punterà all'IP del telefono sulla rete Wi-Fi.

**Si blocca a metà download** — l'app è stata sospesa. Riapri Forgia e riprova
tenendola in primo piano.

**zsign fallisce** — quasi sempre `.p12` e `.mobileprovision` non sono la coppia
giusta: il certificato dentro il profilo deve essere lo stesso del `.p12`.

**Con un certificato Developer a pagamento** le app durano un anno e il profilo deve
elencare l'UDID. Con un Apple ID gratuito la firma dura 7 giorni ed è meglio usare
AltStore, che la rinnova da solo.

---

## Licenza

Codice di Forgia: MIT. zsign è MIT, Zip è MIT, OpenSSL ha la sua licenza Apache 2.0.
Nessun codice di Feather (GPL-3) è stato riusato.
