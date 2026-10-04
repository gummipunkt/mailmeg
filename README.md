# MailMeG

**MailMeG** steht für **Mail Me Google Mail**: ein nativer Gmail-Client für macOS (SwiftUI, AppKit und WebKit), ohne Web-Wrapper.
MailMeG greift direkt über die [Gmail REST API](https://developers.google.com/gmail/api) auf dein Postfach zu
und nicht über IMAP und nicht über eine eingebettete gmail.com-Seite.

## Funktionen

- **Ohne Konto ausprobieren**: Im Willkommensbildschirm öffnet „Erst mal ohne Konto ausprobieren“ ein Demo-Postfach mit Beispiel-E-Mails.

- **Mehrere Gmail-Konten** gleichzeitig, mit Anmeldung per Google OAuth (PKCE) im System-Anmeldefenster
- **Tokens im macOS-Schlüsselbund**, Passwörter sieht die App nie
- **Seitenleiste** mit Posteingang, Markiert, Wichtig, Gesendet, Entwürfe, Alle Nachrichten, Spam, Papierkorb und eigenen Labels (verschachtelt), jeweils mit Ungelesen-Zählern
- **Konversationsansicht** wie in Gmail, ältere gelesene Nachrichten werden eingeklappt
- **Sichere HTML-Darstellung**: JavaScript ist aus und externe Inhalte (Tracking-Pixel) sind standardmäßig blockiert, per Klick oder Einstellung lassen sie sich nachladen. Links öffnen im Browser.
- **Inline-Bilder** (`cid:`) und **Anhänge**: öffnen oder sichern
- **Suche** mit der vollen Gmail-Syntax (`from:`, `has:attachment`, `older_than:` …)
- **Aktionen**: Archivieren, Löschen, Wiederherstellen, Spam, Gelesen/Ungelesen, Stern
- **Rich-Text-Editor**: Fett, Kursiv, Unterstrichen, Durchgestrichen, Listen, Links, Schriftgröße und Farbe – verschickt als HTML mit der Gmail-Signatur
- **Empfängerdetails** mit der genauen Zieladresse (auch bei „mich“), **Quelltext** (⌥⌘U) und **alle Header** (⇧⌘H) jeder E-Mail
- **Abrufintervall** einstellbar (30 Sekunden bis 1 Stunde oder manuell)
- **Design im Stil von Airmail** mit Glas-Oberflächen und runden Buttons, Avatare in der Liste optional
- **Google Kalender**: Tages- und Wochenansicht mit Mini-Monat und Agenda, „Heute“ in der Seitenleiste,
  Einladungen in E-Mails mit Zusagen/Vielleicht/Absagen, neue Termine – auch direkt aus einer E-Mail (⌥⌘E)
- **Entwürfe** werden beim Schreiben automatisch in Gmail gesichert und lassen sich jederzeit weiterbearbeiten
- **Verfassen, Antworten, Allen antworten, Weiterleiten** inklusive Anhängen. Antworten landen im richtigen Gmail-Thread (`threadId`, `In-Reply-To`, `References`).
- **Neue Mails**: Polling über die History-API, Dock-Symbol mit Zähler ungelesener E-Mails
- **Mitteilungen**: Klick öffnet die Konversation, Antworten, Als gelesen markieren und Archivieren direkt in der Mitteilung
- **Tastaturkürzel** wie in Apple Mail: ⌘N, ⌘R, ⇧⌘R, ⇧⌘F, ⌃⌘A, ⌘⌫, ⇧⌘U, ⇧⌘L, ⇧⌘N, ⌥⌘U, ⇧⌘H, ⌥⌘↑/↓, ⌥⌘K (Kalender), ⌥⌘N (neuer Termin), ⌥⌘E (Termin aus E-Mail)

## Installation (fertige DMG, ohne Xcode)

1. **[MailMeG.dmg herunterladen](https://github.com/gummipunkt/mailmeg/releases/latest/download/MailMeG.dmg)**
   (aktuelle stabile Version, Universal: Apple Silicon und Intel, macOS 14 oder neuer).
   Alle Versionen stehen unter [Releases](https://github.com/gummipunkt/mailmeg/releases), den neuesten
   Entwicklungsstand gibt es als [Development-Build](https://github.com/gummipunkt/mailmeg/releases/download/nightly/MailMeG.dmg).
2. DMG öffnen und **MailMeG** in den Ordner **Programme** ziehen.
3. **Erster Start:** Die App ist nicht mit einem kostenpflichtigen Apple-Entwicklerzertifikat signiert
   und nicht notarisiert, deshalb blockiert macOS sie beim ersten Öffnen. So gibst du sie frei:
   - MailMeG einmal per Doppelklick öffnen und die Warnung mit *Fertig* schließen.
   - *Systemeinstellungen → Datenschutz & Sicherheit* öffnen, nach unten scrollen und bei
     „MailMeG wurde blockiert“ auf **Dennoch öffnen** klicken.

   Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/MailMeG.app`
4. Beim ersten Start fragt MailMeG nach deiner **Google-OAuth-Client-ID**, siehe Abschnitt 1.

Nach einem Update kann macOS einmalig fragen, ob MailMeG auf den Schlüsselbund-Eintrag zugreifen darf.
Dann *Immer erlauben* wählen.

## Voraussetzungen zum selbst Bauen

- macOS 14 (Sonoma) oder neuer
- Xcode 15.3 oder neuer (die Command Line Tools reichen nicht)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Ein eigenes Google-Cloud-Projekt mit OAuth-Client (kostenlos, siehe unten)

## 1. Google-Cloud-Projekt einrichten (einmalig, ca. 5 Minuten)

Google erlaubt Gmail-Zugriff nur über einen registrierten OAuth-Client. Für die private Nutzung legst du ihn selbst an:

1. Öffne die [Google Cloud Console](https://console.cloud.google.com/) und lege ein **neues Projekt** an, z. B. „MailMeG“.
2. **Gmail API und Google Calendar API aktivieren**: *APIs & Dienste → Bibliothek → „Gmail API“ → Aktivieren*,
   danach genauso **„Google Calendar API“** (für den Kalender).
3. **OAuth-Zustimmungsbildschirm** (*Google Auth Platform*):
   - *Branding*: App-Name „MailMeG“ und deine E-Mail-Adresse eintragen.
   - *Zielgruppe*: Nutzertyp **Extern** wählen. Unter *Testnutzer* deine Gmail-Adresse(n) hinzufügen.
   - *Datenzugriff* (optional): die Bereiche `…/auth/gmail.modify`, `…/auth/calendar.readonly` und
     `…/auth/calendar.events` hinzufügen.
4. **OAuth-Client anlegen**: *Clients → Client erstellen*
   - Anwendungstyp: **iOS**. Google verwendet diesen Typ auch für macOS-Apps, er braucht kein Client-Secret.
   - Bundle-ID: `de.mailmeg.app`
   - Die angezeigte **Client-ID** kopieren (`…apps.googleusercontent.com`).

> **Wichtig, Token-Laufzeit:** Solange die App im Google-Projekt im Status *Testen* ist, laufen Refresh-Tokens
> nach **7 Tagen** ab, und du musst dich dann neu anmelden (MailMeG zeigt dafür „Erneut anmelden“).
> Das umgehst du, indem du unter *Zielgruppe* auf **„App veröffentlichen“** klickst. Für den Eigengebrauch
> ist keine Google-Verifizierung nötig. Beim Login erscheint dann einmalig der Hinweis „Google hat diese App
> nicht überprüft“, über *Erweitert → Weiter zu MailMeG* geht es weiter.
> Mit einem Google-Workspace-Konto kannst du stattdessen den Nutzertyp *Intern* wählen.

## 2. Selbst bauen (optional)

```bash
git clone <dieses Repo> && cd mailmeg

# optional: Client-ID fest einbauen (die Datei ist git-ignoriert)
echo 'GOOGLE_CLIENT_ID = 1234567890-abc.apps.googleusercontent.com' > Config/Secrets.xcconfig

make open        # erzeugt Mailmeg.xcodeproj mit XcodeGen und öffnet Xcode
```

In Xcode das Schema **MailMeG** wählen und mit ⌘R starten. Ohne `Secrets.xcconfig` fragt die App beim
ersten Start nach der Client-ID.

Weitere Befehle:

```bash
make test        # Unit-Tests der MailmegKit-Bibliothek
# UI-Tests (klicken sich im Demo-Modus durch die App): in Xcode ⌘U
make build       # Release-Build nach build/Build/Products/Release/MailMeG.app
```

Jeder Push baut die App außerdem per GitHub Actions auf macOS, führt Unit- und UI-Tests aus und erzeugt
`MailMeG.dmg`. Pushes auf `main` aktualisieren den
[Development-Build](https://github.com/gummipunkt/mailmeg/releases/tag/nightly).

## Screenshots für die Website

Beispielbilder des Demo-Postfachs (Deutsch/Englisch, hell/dunkel, Verfassen, Header, Einstellungen) liegen in
`Design/Screenshots/` und werden bei jedem Push von der CI unter
`https://github.com/gummipunkt/mailmeg/releases/download/screenshots/landing-de-inbox-light.png` usw. aktualisiert.
Die CI hat nur ein 1024×768-Display; Retina-Bilder in doppelter Auflösung erzeugt `make screenshots` auf dem eigenen Mac.

## Versionen und Releases

Die Versionsnummer steht an genau einer Stelle: `MARKETING_VERSION` in `Config/Mailmeg.xcconfig`.
Die Build-Nummer setzt die CI automatisch (fortlaufende Nummer des Workflow-Laufs). Beides zeigt die App
unter *MailMeG → Über MailMeG* und in den Einstellungen.

Neue Version veröffentlichen:

1. `MARKETING_VERSION` in `Config/Mailmeg.xcconfig` erhöhen, z. B. auf `1.1.0`.
2. In `CHANGELOG.md` einen Abschnitt `## [1.1.0] – Datum` ergänzen.
3. Nach `main` pushen.

Die CI merkt, dass es für `v1.1.0` noch kein Release gibt, legt Tag und Release „MailMeG 1.1.0“ an und hängt
`MailMeG.dmg` und `MailMeG-1.1.0.dmg` an. Die Release-Notizen kommen aus dem CHANGELOG. Alternativ löst auch
ein gepushter Tag `v1.1.0` das Release aus. Der Tag muss dann zu `MARKETING_VERSION` passen.

## Sprache

MailMeG gibt es auf Deutsch und Englisch. Die App folgt der Reihenfolge unter
*Systemeinstellungen → Allgemein → Sprache & Region*. Steht Deutsch vor Englisch, ist die Oberfläche deutsch.

## Roadmap

- Offline-Cache (SwiftData) und Delta-Sync über `history.list`
- Mehrfachauswahl in der Liste, Labels zuweisen per Drag & Drop
- Gmail-Kategorien (Allgemein, Werbung, Soziale Netzwerke …)

## English

MailMeG (“Mail Me Google Mail”) is a native Gmail client for macOS (SwiftUI) that talks to the Gmail REST API directly instead of
wrapping the Gmail website. The interface is available in English and German and follows your macOS language
order. Highlights: multiple accounts, Gmail aliases and signatures, drafts synced with Gmail, a rich text
editor, message source and headers, Google Calendar (day/week view, invitations with RSVP, events from emails),
configurable fetch interval and an Airmail-style glass design.

1. Download **[MailMeG.dmg](https://github.com/gummipunkt/mailmeg/releases/latest/download/MailMeG.dmg)**
   (universal, macOS 14 or later) and drag MailMeG into *Applications*.
2. The app is not notarized: open it once, then choose *System Settings → Privacy & Security → Open Anyway*
   (or run `xattr -dr com.apple.quarantine /Applications/MailMeG.app`).
3. Create your own Google Cloud OAuth client of type **iOS** (bundle ID `de.mailmeg.app`) with the Gmail API and the
   Google Calendar API enabled, paste the client ID on first launch and sign in. Section 1 above describes every step. Or try the
   demo mailbox first.

## Impressum

© 2026 Patrick Walter
Kontakt / Contact: [www.gummipunkt.eu](https://www.gummipunkt.eu) · [mailmeg@gummipunkt.eu](mailto:mailmeg@gummipunkt.eu)
