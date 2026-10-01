# Changelog

Alle nennenswerten Änderungen an Mailmeg. Versionen folgen [Semantic Versioning](https://semver.org/lang/de/).
All notable changes to Mailmeg. Versions follow [Semantic Versioning](https://semver.org/).

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
