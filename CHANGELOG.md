# Changelog

Alle nennenswerten Änderungen an Mailmeg. Versionen folgen [Semantic Versioning](https://semver.org/lang/de/).
All notable changes to Mailmeg. Versions follow [Semantic Versioning](https://semver.org/).

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
