# Changelog

Alle nennenswerten Änderungen an MailMeG. Versionen folgen [Semantic Versioning](https://semver.org/lang/de/).
All notable changes to MailMeG. Versions follow [Semantic Versioning](https://semver.org/).

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
