# Changelog

Alle nennenswerten Änderungen an MailMeG. Versionen folgen [Semantic Versioning](https://semver.org/lang/de/).
All notable changes to MailMeG. Versions follow [Semantic Versioning](https://semver.org/).

## [1.9.0] – 2026-10-07

- **Kalender als eigener Tab**: oben in der Seitenleiste zwischen „Mail“ und „Kalender“ wechseln (⌘1 / ⌘2); der Kalender nutzt die ganze Fensterbreite, das Postfach bleibt beim Zurückwechseln erhalten
  · **Calendar as its own tab**: switch between “Mail” and “Calendar” at the top of the sidebar (⌘1 / ⌘2); the calendar uses the full window width, the mailbox stays as it was when you switch back
- Alle Konten in einem Kalender: die Seitenleiste zeigt den Monat, die Kalender jedes Kontos zum Ein- und Ausblenden (schreibgeschützte mit Schloss) und „Wartet auf deine Antwort“ mit offenen Einladungen
  · All accounts in one calendar: the sidebar shows the month, each account’s calendars to show or hide (read-only ones with a lock) and “Waiting for your answer” with open invitations
- Neue Agenda-Ansicht und Terminsuche (⌘F); ganztägige Termine laufen über mehrere Tage, offene Einladungen sind gestrichelt, Abwesenheiten schraffiert, Fokuszeit markiert, der Arbeitsort steht neben dem Datum
  · New agenda view and event search (⌘F); all-day events span several days, open invitations are dashed, out-of-office time is striped, focus time is marked, the working location is shown next to the date
- **Mehrere E-Mails auswählen**: ⌘A in der Liste, ⇧/⌘-Klick oder „Alle auswählen“ unter der Suche – auf Wunsch über alle Seiten der Suchergebnisse; dann gemeinsam archivieren, löschen, als (un)gelesen oder Spam markieren, per Button, Rechtsklick oder Tastenkürzel
  · **Select several emails**: ⌘A in the list, ⇧/⌘-click or “Select All” below the search – across all pages of search results if you like; then archive, delete, mark as (un)read or spam together, via button, right-click or shortcut

## [1.8.1] – 2026-10-06

- Suchfeld und Kopfzeile der Nachrichtenliste sowie die Buttonleiste über der Konversation haben jetzt einen Milchglas-Hintergrund; beim Scrollen vermischen sich E-Mails nicht mehr mit den Bedienelementen
  · The message list header with the search field and the button bar above the conversation now have a frosted background; scrolling emails no longer mix with the controls

## [1.8.0] – 2026-10-05

- Dateien über Google Drive senden: der neue Button „Google Drive“ lädt Dateien hoch und fügt einen Link in die E-Mail ein – ideal für ZIPs und große Dateien; mit Fortschrittsanzeige
  · Send files via Google Drive: the new “Google Drive” button uploads files and puts a link into the email – ideal for ZIPs and large files; with progress display
- Automatisch über Drive: Anhänge, die die E-Mail über das Gmail-Limit bringen würden, und Dateitypen, die Gmail sperrt (z. B. .dmg, .exe, .iso), gehen als Drive-Link raus
  · Automatically via Drive: attachments that would push the email over Gmail’s limit and file types Gmail blocks (e.g. .dmg, .exe, .iso) are sent as Drive links
- Freigabe wählbar: „Jeder mit dem Link“ oder „Nur Empfänger“; die Dateien liegen in Drive im Ordner „MailMeG-Anhänge“. MailMeG sieht nur Dateien, die es selbst hochgeladen hat
  · Choose the sharing: “Anyone with the link” or “Recipients only”; the files live in the “MailMeG attachments” folder in Drive. MailMeG only sees files it uploaded itself
- Einmalig nötig: „Google Drive API“ im Google-Cloud-Projekt aktivieren und Drive-Zugriff erlauben (MailMeG fragt beim ersten Mal)
  · Needed once: enable the “Google Drive API” in the Google Cloud project and allow Drive access (MailMeG asks the first time)

## [1.7.0] – 2026-10-05

- Termine bearbeiten und löschen: „Bearbeiten …“ im Termin oder per Rechtsklick; Titel, Zeit, Ort, Gäste und Notizen ändern, Gäste werden auf Wunsch informiert
  · Edit and delete events: “Edit…” in the event or via right-click; change title, time, place, guests and notes, guests are notified if you like
- Termine per Drag & Drop verschieben – in der Tagesansicht in 15-Minuten-Schritten, in der Wochenansicht auch auf einen anderen Tag
  · Move events by drag and drop – in 15-minute steps in the day view, and to another day in the week view
- Monatsansicht mit den Terminen jedes Tages; Doppelklick auf einen Tag öffnet die Tagesansicht
  · Month view with each day’s events; double-click a day to open the day view

## [1.6.0] – 2026-10-04

- **Google Kalender** in MailMeG: „Kalender“ in der Seitenleiste mit Mini-Monat, Agenda der nächsten Tage und Tages-/Wochenansicht (⌥⌘K); Termine in den Farben deiner Kalender, Kalender ein- und ausblendbar
  · **Google Calendar** in MailMeG: “Calendar” in the sidebar with a mini month, an agenda of the coming days and a day/week view (⌥⌘K); events in your calendars’ colours, calendars can be shown or hidden
- „Heute“ in der Seitenleiste: die restlichen Termine des Tages auf einen Blick
  · “Today” in the sidebar: the rest of the day’s events at a glance
- Einladungen in E-Mails erscheinen als Karte mit Datum, Ort und Zusagen/Vielleicht/Absagen; die Antwort geht wie in Gmail an den Organisator
  · Invitations in emails appear as a card with date, place and Accept/Maybe/Decline; the answer goes to the organizer like in Gmail
- Neue Termine anlegen (⌥⌘N), auch direkt aus einer E-Mail (⌥⌘E): Betreff und Beteiligte sind schon eingetragen, Einladungen werden auf Wunsch verschickt
  · Create events (⌥⌘N), also straight from an email (⌥⌘E): subject and people are filled in, invitations are sent if you like
- Bestehende Konten verbinden den Kalender einmalig über „Kalender verbinden“; im Google-Cloud-Projekt muss zusätzlich die „Google Calendar API“ aktiviert sein
  · Existing accounts connect the calendar once via “Connect Calendar”; the “Google Calendar API” must also be enabled in the Google Cloud project

## [1.5.1] – 2026-10-03

- Start hängt nicht mehr (Symbol hüpft nur): Die gespeicherten Anmeldungen werden jetzt im Hintergrund aus dem Schlüsselbund gelesen, das Fenster erscheint sofort mit „Konten werden geladen …“ und einem Hinweis, falls macOS nach dem Schlüsselbund fragt
  · Launch no longer hangs (icon only bounces): saved sign-ins are now read from the keychain in the background, the window appears right away with “Loading accounts…” and a hint in case macOS asks about the keychain

## [1.5.0] – 2026-10-02

- Neuer Name: **MailMeG** – „Mail Me Google Mail“. App, Menüs, Fenster, Mitteilungen und Download heißen jetzt so (`MailMeG.app`, `MailMeG.dmg`); Einstellungen und Anmeldungen bleiben erhalten
  · New name: **MailMeG** – “Mail Me Google Mail”. App, menus, windows, notifications and download now use it (`MailMeG.app`, `MailMeG.dmg`); settings and sign-ins are kept

## [1.4.2] – 2026-10-02

- Fenster für Header und Quelltext im MailMeG-Design: Glas-Hintergrund, Karten, runde Buttons, Umschalter Header/Quelltext, Header-Filter, hervorgehobene Header-Namen
  · Headers and source window in the MailMeG design: glass background, cards, round buttons, headers/source switch, header filter, highlighted header names
- App-Symbol mit neu zentriertem Briefträger
  · App icon with the re-centred mail carrier

## [1.4.1] – 2026-10-02

- Antworten gehen zuverlässig von der Adresse raus, an die die E-Mail ging: An und Cc haben Vorrang vor „Delivered-To“ (vorher konnte die Hauptadresse gewinnen), eigene Nachrichten behalten ihren Absender, sonst helfen Weiterleitungs-Header und frühere Nachrichten der Konversation
  · Replies reliably go out from the address the email was sent to: To and Cc take precedence over “Delivered-To” (the main address could win before), own messages keep their sender, otherwise forwarding headers and earlier messages of the conversation are used
- Gmails „Wichtig“-Markierung erscheint jetzt auch in der Nachrichtenliste
  · Gmail's “Important” marker is now also shown in the message list

## [1.4.0] – 2026-10-02

- Neues App-Symbol: der MailMeG-Briefträger
  · New app icon: the MailMeG mail carrier
- Umlaute und Sonderzeichen werden korrekt angezeigt, auch wenn der Absender einen falschen Zeichensatz angibt (z. B. „fÃ¼r“ statt „für“)
  · Umlauts and special characters display correctly even when the sender declares the wrong charset (e.g. “fÃ¼r” instead of “für”)
- Mitteilungen: Klick öffnet die Konversation; Antworten, Als gelesen markieren und Archivieren direkt in der Mitteilung; Banner auch, wenn MailMeG im Vordergrund ist; gelesene Konversationen verschwinden aus der Mitteilungszentrale
  · Notifications: a click opens the conversation; reply, mark as read and archive right from the notification; banners also while MailMeG is in front; read conversations are removed from Notification Center
- Zähler für ungelesene E-Mails im Dock-Symbol aktualisiert sich sofort (abschaltbar); Einstellungen zeigen, ob macOS Mitteilungen erlaubt, mit Test-Mitteilung
  · The unread counter on the Dock icon updates right away (can be turned off); Settings show whether macOS allows notifications, with a test notification

## [1.3.0] – 2026-10-02

- Neues Design im Stil von Airmail: Glas-Oberflächen, runde Buttons, zentrierter Listentitel mit Suchfeld, aufgeräumte Liste ohne Avatare (in den Einstellungen wieder einschaltbar), großer Betreff und Navigation zur vorherigen/nächsten Konversation (⌥⌘↑/↓) – die System-Titelleiste bleibt
  · New Airmail-style design: glass surfaces, round buttons, centred list title with search field, clean list without avatars (can be switched back on in Settings), large subject and previous/next conversation navigation (⌥⌘↑/↓) – the system title bar stays
- Rich-Text-Editor beim Verfassen: Fett (⌘B), Kursiv (⌘I), Unterstrichen (⌘U), Durchgestrichen, Aufzählungen und nummerierte Listen, Links (⌘K), Schriftgröße, Textfarbe; verschickt als HTML mit Gmail-Signatur
  · Rich text editor: bold (⌘B), italic (⌘I), underline (⌘U), strikethrough, bulleted and numbered lists, links (⌘K), text size and colour; sent as HTML together with the Gmail signature
- Empfänger mit genauer Adresse: im Kopf jeder Nachricht steht, an welche Adresse sie ging (auch bei „mich“); „Details“ zeigt Von, Antwort an, An, Cc, Bcc, Zugestellt an, Datum
  · Recipients with their exact address: each message header shows which address it went to (also for “me”); “Details” lists From, Reply-To, To, Cc, Bcc, Delivered-To and Date
- Quelltext (⌥⌘U) und alle Header (⇧⌘H) einer E-Mail in eigenem Fenster, mit Kopieren und Sichern als .eml
  · Message source (⌥⌘U) and all headers (⇧⌘H) in their own window, with copy and save as .eml
- Abrufintervall einstellbar (30 Sekunden bis 1 Stunde oder manuell), Zeit des letzten Abrufs in der Seitenleiste; Labels direkt aus der Konversation zuweisen
  · Configurable fetch interval (30 seconds to 1 hour, or manually), last fetch time in the sidebar; assign labels right from the conversation

## [1.2.0] – 2026-10-01

- Entwürfe: MailMeG sichert E-Mails beim Schreiben automatisch als Gmail-Entwurf (auch beim Schließen des Fensters, ⌘S sofort), synchron mit Gmail im Web und auf dem Handy
  · Drafts: MailMeG saves messages as Gmail drafts while you write (also when closing the window, ⌘S to save now), in sync with Gmail on the web and on your phone
- Entwürfe bearbeiten per Doppelklick im Ordner „Entwürfe“ oder über „Bearbeiten“ in der Konversation; „Verwerfen“ löscht den Entwurf auch in Gmail
  · Edit drafts by double-clicking them in Drafts or via “Edit” in the conversation; “Discard” also deletes the draft in Gmail
- Beim Senden wird der gespeicherte Entwurf entfernt; Entwürfe sind in der Liste markiert
  · Sending removes the saved draft; drafts are marked in the message list

## [1.1.0] – 2026-10-01

- Absender wählbar: alle in Gmail unter „Senden als“ hinterlegten Adressen, Standard-Absender pro Konto in den Einstellungen; Antworten gehen automatisch von der Adresse raus, an die die Mail ging
  · Choose the sender: all Gmail “Send mail as” addresses, default sender per account in Settings; replies automatically use the address the message was sent to
- Signaturen aus Gmail werden eingefügt (auf Wunsch auch bei Antworten) und beim Absenderwechsel getauscht; im Versand bleiben Links und Formatierung der Signatur erhalten
  · Gmail signatures are inserted (optionally in replies too) and swapped when changing the sender; links and formatting are kept when sending
- Einstellung, ob Antworten über oder unter dem Zitat geschrieben werden – der Cursor steht direkt an der richtigen Stelle
  · Setting to write replies above or below the quoted message – the cursor starts in the right place
- Antwort-Adresse („Reply-To“) des Absenders wird übernommen; E-Mails werden zusätzlich als HTML verschickt
  · The sender's reply-to address is used; messages are also sent as HTML

## [1.0.0] – 2026-10-01

Erste Version · First release

- Native macOS-App (SwiftUI), die direkt über die Gmail-API arbeitet – kein Web-Wrapper
  · Native macOS app (SwiftUI) talking to the Gmail API directly – no web wrapper
- Mehrere Konten, Anmeldung per Google OAuth (PKCE), Tokens im Schlüsselbund
  · Multiple accounts, Google OAuth sign-in (PKCE), tokens stored in the Keychain
- Posteingang, Labels, Suche mit Gmail-Syntax, Filter „Ungelesen“
  · Inbox, labels, search with Gmail syntax, “Unread” filter
- Konversationsansicht mit sicherer HTML-Darstellung (externe Inhalte blockiert), Anhänge, Inline-Bilder
  · Conversation view with safe HTML rendering (remote content blocked), attachments, inline images
- Verfassen, Antworten, Allen antworten, Weiterleiten, Schnellantwort
  · Compose, reply, reply all, forward, quick reply
- Archivieren, Löschen, Spam, Gelesen/Ungelesen, Markieren – auch per Hover und Tastenkürzel
  · Archive, delete, spam, read/unread, star – also on hover and via keyboard shortcuts
- Mitteilungen und Dock-Badge bei neuen E-Mails
  · Notifications and Dock badge for new email
- Deutsche und englische Oberfläche, helles und dunkles Erscheinungsbild
  · German and English interface, light and dark appearance
- Demo-Postfach zum Ausprobieren ohne Konto
  · Demo mailbox to try the app without an account
- Sparsamer Umgang mit dem Gmail-Kontingent (Cache, gebündelte Zähler, Backoff)
  · Careful use of the Gmail quota (cache, batched counters, backoff)
