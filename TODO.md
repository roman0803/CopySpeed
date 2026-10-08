# Übertragungsgeschwindigkeit – To-Do

Ziel: Beim Kopieren im Finder (Netzwerk, externe Platte, …) die aktuelle
Übertragungsgeschwindigkeit (MB/s bzw. Mbit/s) direkt am Kopierfenster anzeigen.

## Grundsatzentscheidung

Das Finder-Kopierfenster selbst lässt sich **nicht** verändern. Code in den
Finder zu injizieren (SIMBL/mach_inject) geht nur mit abgeschaltetem SIP und
bricht bei jedem Update. Stattdessen:

**Eigene Menüleisten-App mit einem schwebenden Overlay (`NSPanel`), das direkt
am Finder-Kopierfenster klebt** und dort z. B. `↓ 112,4 MB/s · 899 Mbit/s`
anzeigt. Für den Nutzer sieht das aus wie ein Teil des Fensters.

Datenquellen (**Stand nach Spikes 2026-10-08**):

1. **Accessibility-API – primäre Quelle** ✅ verifiziert (lokal + SMB).
   Kopierfenster (`id="Progress"`) liefert Position, alle Vorgänge, Gesamtgröße
   (Statustext) und Fortschritt (`AXProgressIndicator`, 0…1).
   Bytes = Balkenwert × Gesamtgröße → Δ/Δt, über ~3 s geglättet.
2. **`NSProgress`-Abo** ✅ verifiziert, optional: exakte Bytes ohne Berechtigung,
   aber nur für direkte Kinder des abonnierten Ordners (bräuchte FSEvents-Trick).
3. **Systemzähler** (IOKit/sysctl) ✅ verifiziert: Fallback, nicht vorgangsspezifisch.

## Phase 0 – Machbarkeits-Spikes (zuerst!)

- [x] Spike A: AX-Hierarchie des Kopierfensters (macOS 27.2) ✅ 2026-10-08:
      `AXWindow title="Kopieren" id="Progress"` (ID sprachunabhängig, liegt in
      Finder-`AXWindows`) → `AXScrollArea` → je Vorgang: `AXImage`,
      `AXStaticText` „Kopieren von „<Name>“ nach „<Ziel>““, `AXProgressIndicator`
      (0…1), `AXButton` „Status stoppen“, `AXStaticText` „2,00 GB von 3,74 GB - …“.
      Achtung: Finder-Listenansicht hat für die Zieldatei ebenfalls einen
      `AXProgressIndicator` → nur Fenster mit id="Progress" auswerten.
      Bedienungshilfen-Liste heißt in macOS 27 evtl. „Gerätesteuerung und Datenzugriff“.
- [x] Spike A2: Mehrere parallele Kopien ✅ 2026-10-08 (SMB-NAS, Gigabit):
      Vorgänge liegen nacheinander in derselben `AXScrollArea`; Fenster wächst
      um ~61 px pro Vorgang (88 → 149 px). Zuordnung Titel/Balken/Status klappt.
      Einzelkopie ~117 MB/s (≈ 940 Mbit/s = Gigabit voll), parallel 2× ~55–67 MB/s,
      Σ ~110–135 MB/s. Text- und Balken-Berechnung weichen < 2 % ab.
- [x] Spike C: `NSProgress.addSubscriber(forFileURL:)` ✅ funktioniert (Details oben).
      Getestet mit Finder-Kopien auf HFS+-Disk-Images: ~400–840 MB/s, deckt sich mit IOKit.
- [x] Spike D: IOKit-Disk-Stats + Interface-Bytezähler auslesen und mit
      echter Kopie vergleichen. ✅ 2026-10-08: ~370 MB/s gemessen vs. 368 MB/s laut dd.
- [x] Ergebnis (nach SMB-Test revidiert): **AX allein reicht** – Kopierfenster
      liefert Position, Vorgänge, Gesamtgröße (Text) und Fortschritt (Balken,
      Double-Genauigkeit). Bytes = Balkenwert × Gesamtgröße. Kein FSEvents-/
      NSProgress-Umweg nötig. `NSProgress` bleibt optionale Präzisions-Erweiterung.
- [x] Spike B: `ax-spike watch` live getestet ✅ (siehe A2).
- [ ] Optional: Spike C auf SMB/externer Platte wiederholen (nur falls NSProgress doch gebraucht wird).

## Phase 1 – Grundgerüst

- [x] Xcode-Projekt via xcodegen (`project.yml`), „CopySpeed“, `com.roman.copyspeed`,
      Menüleisten-App (`LSUIElement`), nicht sandboxed, macOS 14+, signiert mit
      Apple Development (Team 2M4LLPLRLS) → AX-Freigabe überlebt Neubauten.
- [x] Onboarding für Bedienungshilfen-Berechtigung (`AXIsProcessTrustedWithOptions`,
      Link in Systemeinstellungen).
- [x] Menüleisten-Icon mit Status (aktiv / keine Kopie / Berechtigung fehlt).

## Phase 2 – Kopierfenster erkennen

- [x] Erkennung per Polling alle 0,5 s (statt `AXObserver`) – reicht, bewährt.
- [ ] Optional: auf `AXObserver` umstellen, falls Leerlauf-CPU zu hoch.
- [x] Kopierfenster eindeutig identifizieren (sprachunabhängig, nicht nur
      über deutschen Titel „Kopieren“).
- [x] Mehrere gleichzeitige Kopiervorgänge im selben Fenster unterstützen:
      Geschwindigkeit **pro Vorgang** (Zeile im Kopierfenster) + **Gesamtsumme**.
      Optional: Name der aktuell kopierten Datei (falls AX/NSProgress das liefert).
- [ ] Auch Finder-Fortschritt in der Symbolleiste (Kreis-Indikator /
      Popover) berücksichtigen, falls das Fenster minimiert/geschlossen ist.

## Phase 3 – Geschwindigkeit berechnen

- [x] Parser für Byte-Angaben (KB/MB/GB/TB, Dezimal-Komma, Lokalisierung
      de/en; Finder nutzt Basis 1000).
- [x] Sampling (z. B. alle 500 ms) + Glättung (gleitender Durchschnitt bzw.
      EMA über ~3 s), Ausreißer bei Dateiwechseln abfangen.
- [x] Zusätzlich: Durchschnitt seit Start (angezeigt), Spitze (berechnet, noch nicht angezeigt).
- [x] Einheiten umschaltbar: MB/s, Mbit/s, beides.
- [x] Unit-Tests für Parser und Rechenlogik (14 Tests, grün).

## Phase 4 – Overlay-UI

- [x] `NSPanel` (nonactivating, borderless, `.floating`/passend zum
      Finder-Fenster, `ignoresMouseEvents`), Liquid-Glass-/Vibrancy-Look.
- [x] Position an Kopierfenster koppeln (unten rechts innerhalb oder direkt
      darunter), mitbewegen, bei Space-Wechsel/Vollbild korrekt verhalten.
- [x] Ein Overlay-Eintrag pro Kopiervorgang.
- [ ] Optional: Mini-Sparkline der Geschwindigkeit.
- [x] Ausblenden, wenn Kopie fertig / Fenster weg.

## Phase 5 – Einstellungen & Extras

- [x] Einheit + Start bei Anmeldung im Menü (vorerst kein eigenes Fenster).
- [ ] Optional: Einstellungsfenster (Position, Glättung, Sparkline).
- [x] Geschwindigkeit optional auch in der Menüleiste anzeigen.
- [ ] Optional: Fallback-Modus (Phase-0-D) für Kopien außerhalb des Finders
      (Terminal `cp`, `rsync`).

## Phase 6 – Test & Release

- [x] Getestet 2026-10-08 von Roman: auf NAS (SMB), vom NAS, auf externe
      Platte – Position, Mitbewegen und Werte korrekt.
- [x] Viele Dateien / „Ersetzen?“-Dialog getestet (Roman). Gefixt 2026-10-08:
      Finder zählt im Titel die *verbleibenden* Objekte herunter („Kopieren von
      941 Objekten …“) → Vorgangs-Schlüssel ignoriert Zahlen; Zeilen nach
      Y-Position sortiert; Name „42 Objekte“ statt Zielordner.
      Diagnose: `defaults write com.roman.copyspeed debugLog -bool YES`
      → `~/Library/Logs/CopySpeed/debug.log`.
- [ ] Rest der Testmatrix: SMB-Share, AFP/NFS falls vorhanden, USB-SSD, HDD,
      Thunderbolt, viele kleine Dateien vs. eine große Datei, parallele Kopien,
      Abbrechen/Pausieren, Konflikt-Dialog („Ersetzen?“).
- [ ] Performance: CPU-Last im Leerlauf ~0 %.
- [ ] Signieren + Notarisieren, DMG, optional Sparkle-Updates.

## Risiken

- Apple ändert die AX-Struktur des Kopierfensters → Parser robust halten,
  Fallback auf Systemzähler.
- Gesamtgröße stammt aus gerundetem Text (z. B. „3,74 GB“) → Fehler < 0,3 %, unkritisch.
- App Store nicht möglich (keine Sandbox) → Vertrieb direkt per DMG.
