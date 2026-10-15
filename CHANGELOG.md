# Changelog

## [0.2.1] – 2026-10-15

### Behoben
- Bei mehreren gleichzeitigen Kopien fehlte die Geschwindigkeit am Ende mancher Statuszeilen dauerhaft.
  Ursache: CopySpeed merkte sich je Kopie den längsten jemals gesehenen Finder-Text (z. B. „Verbleibende Zeit
  berechnen …“ am Anfang) und blendete die Zahl danach nie wieder ein. Jetzt zählt der aktuelle Text: Die Zahl
  verschwindet sofort, wenn der Text zu lang wird, und kommt zurück, sobald er 1–1,5 s lang passt.
- Mit der Einheit „Mbit/s“ erschien in den Statuszeilen praktisch nie eine Zahl (Platz für „8.888 Mbit/s“
  reservierte zu viel). Jetzt kompakt ab 1 Gbit/s („2,1 Gbit/s“).
- Wird Finders Text neben einer sichtbaren Zahl länger, verschwindet die Zahl innerhalb von ~0,1 s statt erst
  nach bis zu 0,5 s.

### Geändert
- Kompaktes Format in den Statuszeilen ab 1 GB/s: „1,25 GB/s“ statt „1.250 MB/s“.

## [0.2.0] – 2026-10-13

### Neu
- **Anzeige im Kopierfenster** (neuer Standard): Die Geschwindigkeit steht rechtsbündig in der Titelzeile –
  bei einer Kopie mit Durchschnitt (Ø), bei mehreren als Summe („Gesamt …“). Bei mehreren Kopien zusätzlich
  am Ende jeder sichtbaren Statuszeile, kompakt („321 MB/s“) und ohne Springen, wenn der Finder seinen
  Restzeit-Text wechselt. Bei Platzmangel kürzt sich die Titelzeile automatisch.
- Menüpunkt **„Anzeige“** zum Umschalten zwischen „Im Kopierfenster“ und „Unter dem Kopierfenster“.
- Diagnose-Schnappschüsse der Anzeige (`overlay-*.png`) bei eingeschaltetem `debugLog`.

### Geändert
- Die bisherige Anzeige unter dem Kopierfenster ist jetzt eine **Schublade**, deren oberer Rand verdeckt
  hinter dem Fenster liegt (Menü: „Anzeige“ → „Unter dem Kopierfenster“). Sie zeigt jetzt auch bei einer
  einzelnen Datei den **Namen**.

### Verbessert
- Die Anzeige folgt dem Kopierfenster 30-mal pro Sekunde (vorher alle 0,5 s) und wird sofort neu
  einsortiert, wenn der Finder das Fenster nach vorne holt (vorher erst beim nächsten 0,5-s-Takt).
- Bei Größenänderung des Kopierfensters (Kopie dazu/fertig) wird sofort neu ausgelesen.
- Anzeige wird in Mission Control ausgeblendet.

## [0.1.0] – 2026-10-08

Erste Version.

- Menüleisten-App, die das Finder-Kopierfenster per Accessibility ausliest.
- Geschwindigkeit pro Kopiervorgang mit Durchschnitt, bei mehreren Kopien die Summe – in einer Anzeige
  unter dem Kopierfenster.
- Einheit wählbar (MB/s, Mbit/s, beides), Gesamtgeschwindigkeit in der Menüleiste, Start bei Anmeldung.
- Getestet mit SMB-Netzlaufwerk, externer USB-Platte und lokalen Kopien.

[0.2.1]: https://github.com/roman0803/CopySpeed/releases/tag/v0.2.1
[0.2.0]: https://github.com/roman0803/CopySpeed/releases/tag/v0.2.0
[0.1.0]: https://github.com/roman0803/CopySpeed/releases/tag/v0.1.0
