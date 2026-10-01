# Mailmeg

Ein nativer Gmail-Client für macOS: SwiftUI, AppKit und WebKit, ohne Web-Wrapper.
Mailmeg greift direkt über die [Gmail REST API](https://developers.google.com/gmail/api) auf dein Postfach zu
und nicht über IMAP und nicht über eine eingebettete gmail.com-Seite.

## Funktionen

- **Mehrere Gmail-Konten** gleichzeitig, mit Anmeldung per Google OAuth (PKCE) im System-Anmeldefenster
- **Tokens im macOS-Schlüsselbund**, Passwörter sieht die App nie
- **Seitenleiste** mit Posteingang, Markiert, Wichtig, Gesendet, Entwürfe, Alle Nachrichten, Spam, Papierkorb und eigenen Labels (verschachtelt), jeweils mit Ungelesen-Zählern
- **Konversationsansicht** wie in Gmail, ältere gelesene Nachrichten werden eingeklappt
- **Sichere HTML-Darstellung**: JavaScript ist aus und externe Inhalte (Tracking-Pixel) sind standardmäßig blockiert, per Klick oder Einstellung lassen sie sich nachladen. Links öffnen im Browser.
- **Inline-Bilder** (`cid:`) und **Anhänge**: öffnen oder sichern
- **Suche** mit der vollen Gmail-Syntax (`from:`, `has:attachment`, `older_than:` …)
- **Aktionen**: Archivieren, Löschen, Wiederherstellen, Spam, Gelesen/Ungelesen, Stern
- **Verfassen, Antworten, Allen antworten, Weiterleiten** inklusive Anhängen. Antworten landen im richtigen Gmail-Thread (`threadId`, `In-Reply-To`, `References`).
- **Neue Mails**: Polling über die History-API, Mitteilungen und Dock-Badge
- **Tastaturkürzel** wie in Apple Mail: ⌘N, ⌘R, ⇧⌘R, ⇧⌘F, ⌃⌘A, ⌘⌫, ⇧⌘U, ⇧⌘L, ⇧⌘N

## Installation (fertige DMG, ohne Xcode)

1. **[Mailmeg.dmg herunterladen](https://github.com/gummipunkt/mailmeg/releases/download/latest/Mailmeg.dmg)**
   (Universal: Apple Silicon und Intel, macOS 14 oder neuer). Alle Builds findest du unter
   [Releases](https://github.com/gummipunkt/mailmeg/releases).
2. DMG öffnen und **Mailmeg** in den Ordner **Programme** ziehen.
3. **Erster Start:** Die App ist nicht mit einem kostenpflichtigen Apple-Entwicklerzertifikat signiert
   und nicht notarisiert, deshalb blockiert macOS sie beim ersten Öffnen. So gibst du sie frei:
   - Mailmeg einmal per Doppelklick öffnen und die Warnung mit *Fertig* schließen.
   - *Systemeinstellungen → Datenschutz & Sicherheit* öffnen, nach unten scrollen und bei
     „Mailmeg wurde blockiert“ auf **Dennoch öffnen** klicken.

   Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/Mailmeg.app`
4. Beim ersten Start fragt Mailmeg nach deiner **Google-OAuth-Client-ID**, siehe Abschnitt 1.

Nach einem Update kann macOS einmalig fragen, ob Mailmeg auf den Schlüsselbund-Eintrag zugreifen darf.
Dann *Immer erlauben* wählen.

## Voraussetzungen zum selbst Bauen

- macOS 14 (Sonoma) oder neuer
- Xcode 15.3 oder neuer (die Command Line Tools reichen nicht)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Ein eigenes Google-Cloud-Projekt mit OAuth-Client (kostenlos, siehe unten)

## 1. Google-Cloud-Projekt einrichten (einmalig, ca. 5 Minuten)

Google erlaubt Gmail-Zugriff nur über einen registrierten OAuth-Client. Für die private Nutzung legst du ihn selbst an:

1. Öffne die [Google Cloud Console](https://console.cloud.google.com/) und lege ein **neues Projekt** an, z. B. „Mailmeg“.
2. **Gmail API aktivieren**: *APIs & Dienste → Bibliothek → „Gmail API“ → Aktivieren*.
3. **OAuth-Zustimmungsbildschirm** (*Google Auth Platform*):
   - *Branding*: App-Name „Mailmeg“ und deine E-Mail-Adresse eintragen.
   - *Zielgruppe*: Nutzertyp **Extern** wählen. Unter *Testnutzer* deine Gmail-Adresse(n) hinzufügen.
   - *Datenzugriff* (optional): Bereich `https://www.googleapis.com/auth/gmail.modify` hinzufügen.
4. **OAuth-Client anlegen**: *Clients → Client erstellen*
   - Anwendungstyp: **iOS**. Google verwendet diesen Typ auch für macOS-Apps, er braucht kein Client-Secret.
   - Bundle-ID: `de.mailmeg.app`
   - Die angezeigte **Client-ID** kopieren (`…apps.googleusercontent.com`).

> **Wichtig, Token-Laufzeit:** Solange die App im Google-Projekt im Status *Testen* ist, laufen Refresh-Tokens
> nach **7 Tagen** ab, und du musst dich dann neu anmelden (Mailmeg zeigt dafür „Erneut anmelden“).
> Das umgehst du, indem du unter *Zielgruppe* auf **„App veröffentlichen“** klickst. Für den Eigengebrauch
> ist keine Google-Verifizierung nötig. Beim Login erscheint dann einmalig der Hinweis „Google hat diese App
> nicht überprüft“, über *Erweitert → Weiter zu Mailmeg* geht es weiter.
> Mit einem Google-Workspace-Konto kannst du stattdessen den Nutzertyp *Intern* wählen.

## 2. Selbst bauen (optional)

```bash
git clone <dieses Repo> && cd mailmeg

# optional: Client-ID fest einbauen (die Datei ist git-ignoriert)
echo 'GOOGLE_CLIENT_ID = 1234567890-abc.apps.googleusercontent.com' > Config/Secrets.xcconfig

make open        # erzeugt Mailmeg.xcodeproj mit XcodeGen und öffnet Xcode
```

In Xcode das Schema **Mailmeg** wählen und mit ⌘R starten. Ohne `Secrets.xcconfig` fragt die App beim
ersten Start nach der Client-ID.

Weitere Befehle:

```bash
make test        # Unit-Tests der MailmegKit-Bibliothek
make build       # Release-Build nach build/Build/Products/Release/Mailmeg.app
```

Jeder Push baut die App außerdem per GitHub Actions auf macOS, führt die Tests aus und erzeugt
`Mailmeg.dmg`. Pushes auf `main` aktualisieren das Release
[`latest`](https://github.com/gummipunkt/mailmeg/releases/tag/latest).

## Architektur

```
MailmegKit/              Swift Package, plattformnahe Logik ohne UI, mit Unit-Tests
  OAuth.swift            Google OAuth 2.0 (Authorization Code + PKCE), Token-Refresh (TokenManager)
  GmailClient.swift      Typisierter REST-Client: Labels, Threads, Messages, Anhänge, Senden, History
                         mit automatischem Token-Refresh bei 401 und Backoff bei 429/5xx
  MessageContent.swift   MIME-Baum → HTML/Text/Anhänge, Zeichensätze, HTML↔Text
  MIMEBuilder.swift      RFC 5322/MIME-Erzeugung (UTF-8, RFC 2047/2231, multipart/mixed)
  ReplyBuilder.swift     Empfänger/Betreff/Zitat für Antworten und Weiterleitungen
App/                     SwiftUI-App
  Model/                 AppModel, AccountSession, MailboxModel, ThreadDetailModel (@Observable)
  Views/                 NavigationSplitView mit drei Spalten, WKWebView-Renderer, Compose-Fenster
  Support/               Keychain, Einstellungen, Formatierung
Design/AppIcon.svg       Quelle des App-Icons (daraus werden die PNGs in App/Assets.xcassets erzeugt)
project.yml              XcodeGen-Projektdefinition
```

### Datenschutz und Sicherheit

- Mailmeg spricht nur mit `accounts.google.com`, `oauth2.googleapis.com` und `gmail.googleapis.com`.
  Es gibt keinen eigenen Server und keine Telemetrie.
- Die App läuft in der macOS-Sandbox und darf nur ausgehende Netzwerkverbindungen und vom Nutzer gewählte Dateien.
- Angefragter Scope: `gmail.modify` (lesen, senden, Labels ändern, in den Papierkorb legen).
  Endgültiges Löschen ist damit bewusst nicht möglich.
- Nachrichten-HTML läuft in einem WKWebView ohne JavaScript, mit Content-Security-Policy und einem
  WebKit-Content-Blocker für externe Ressourcen.

## Roadmap

- Entwürfe bearbeiten und automatisch speichern (`drafts`-API)
- Offline-Cache (SwiftData) und Delta-Sync über `history.list`
- Mehrfachauswahl in der Liste, Labels zuweisen per Drag & Drop
- Gmail-Kategorien (Allgemein, Werbung, Soziale Netzwerke …)
- Signaturen aus den Gmail-Einstellungen und Rich-Text-Editor
- Klick auf Mitteilung öffnet die Konversation
- Lokalisierung (Deutsch)
