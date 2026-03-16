# vinyl2tracks – Schallplatten-Rips in Einzeltracks

Toolchain zum Aufteilen langer Audio-Aufnahmen (eine MP3/WAV pro Seite oder Platte) in einzelne Tracks per **Stille-Erkennung** und optionalem **OCR** von Cover/Label für Titel und Metadaten.

**Hinweis zu Spleeter:** [Deezer Spleeter](https://github.com/deezer/spleeter) trennt **Quellen** (Gesang vs. Begleitung), nicht eine Aufnahme in Tracks. Die Track-Trennung macht dieses Projekt mit ffmpeg `silencedetect`. Spleeter kann optional nachgelagert genutzt werden (z.B. pro Track Stems erzeugen).

## Ablauf

1. **Metadaten (zuerst bei 2 Seiten)** – OCR und/oder **MusicBrainz** (erster Versuch bei Katalognummer): Album, Künstler, Trackliste, Jahr, Label, Katalognummer, ggf. Tracks pro Seite.
2. **Track-Split** – `split_by_silence.py`: Eine oder zwei Dateien (Seite A + B) → Tracks in **ein** Verzeichnis (01 … 20). Bei zwei Seiten: `--track-offset` für Seite B.
3. **Umbenennen & Taggen** – `rename_tracks.py`: Alle Infos aus Metadaten in ID3 (Titel, Album, Künstler, Jahr, Label, Katalognummer).
4. **Spleeter (optional)** – Pro Track Stems (vocals/accompaniment) erzeugen.

## Anforderungen

- **ffmpeg** (inkl. ffprobe)
- **Python 3**
- Optional: OCR (siehe unten)
- Optional: **Spleeter** (`pip install spleeter`) für Stem-Separation

## Verwendung

### Nur Tracks aufteilen

```bash
git clone https://github.com/frabartolo/vinyl2tracks.git && cd vinyl2tracks
python3 split_by_silence.py /pfad/zur/aufnahme_seite_a.mp3 -o ./ausgabe
# Ausgabe: 01.mp3, 02.mp3, …
```

Parameter:

- `--noise-db` – Stille-Schwelle (z.B. -28 für Vinyl)
- `--min-silence` – Mindestdauer Stille in Sekunden (default 1.2)
- `--min-track` – Kürzeste Track-Länge (Sekunden); bei `--tracks` ignoriert
- `--tracks` / `-n` – **Erwartete Anzahl Tracks** (z.B. `-n 10`). Die Zeitachse wird in N-1 Regionen geteilt; pro Region wird das längste Stille-Intervall als Trennstelle genutzt. So entstehen genau N Tracks ohne Häufung am Plattenende (Run-out).
- `--format mp3|wav|copy` – Ausgabeformat
- `--track-offset` – Start-Nummer für Dateinamen (z.B. 10 → 11.mp3, 12.mp3 … für Seite B)
- `--dry-run` – Nur Segmente anzeigen, nicht schneiden
- `-v` – Erkannte Stille-Intervalle anzeigen

### Mit OCR (Cover/Label → Metadaten)

OCR wird über **OCR_CMD** oder **OCR_URL** konfiguriert.

**Variante: Befehl (z.B. OpenClaw/DeepSeek)**

Der Befehl erhält den **absoluten Bildpfad** als einziges Argument und gibt den erkannten Text auf **stdout** aus.

```bash
# Beispiel: Wrapper-Skript (siehe ocr_openclaw.example.sh)
export OCR_CMD="/pfad/zu/ocr_openclaw.example.sh"
# oder z.B. lokaler Aufruf:
# export OCR_CMD="tesseract"   # falls tesseract stdin/stdout nutzt, ggf. eigenes Wrapper-Skript

python3 ocr_metadata.py cover.jpg label.jpg --json > metadata.json
python3 rename_tracks.py ./ausgabe --meta metadata.json --dry-run   # Vorschau
python3 rename_tracks.py ./ausgabe --meta metadata.json              # ausführen
```

**Variante: HTTP-API**

```bash
export OCR_URL="http://openclaw:8080/ocr"   # POST Body = Bilddatei
python3 ocr_metadata.py cover.jpg --json > metadata.json
```

**OpenClaw:** Wenn DeepSeek OCR auf dem OpenClaw-Rechner läuft, ein kleines Wrapper-Skript bereitstellen, das z.B. per SSH ein Bild übergibt und die OCR-Ausgabe zurückgibt. Siehe `ocr_openclaw.example.sh`.

### Komplette Pipeline

```bash
# Eine Seite
./run_pipeline.sh /pfad/zu/seite_a.mp3 [ausgabe_ordner]

# Beide Seiten → ein Verzeichnis (01 … 20). Metadaten zuerst (MusicBrainz als erster Versuch).
VINYL_OCR_IMAGES="cover.jpg label.jpg" OCR_CMD=/pfad/zu/ocr_wrapper.sh ./run_pipeline.sh seite_a.mp3 seite_b.mp3 ./ausgabe
# Oder nur Katalognummer (ohne OCR):
VINYL_CATALOG=63168 ./run_pipeline.sh "Louis Armstrong/20 GOLDEN HITS/Seite_1.MP3" "Louis Armstrong/20 GOLDEN HITS/Seite_2.MP3" "./Louis Armstrong/20 GOLDEN HITS/Ausgabe"

# Optional Spleeter
VINYL_USE_SPLEETER=1 ./run_pipeline.sh seite_a.mp3
```

Die Pipeline lädt bei vorhandener Katalognummer (aus OCR oder `VINYL_CATALOG`) **zuerst** die Metadaten von MusicBrainz (Album, Künstler, alle Tracktitel, Jahr, Label, Katalognummer, ggf. Tracks pro Seite). Anschließend werden beide Seiten in ein gemeinsames Verzeichnis geschnitten und alle Infos in die MP3-Tags übernommen.

## Konfiguration (Umgebung)

| Variable | Bedeutung |
|----------|-----------|
| `OCR_CMD` / `VINYL_OCR_CMD` | Befehl für OCR; erhält Bildpfad als 1. Argument, liefert Text auf stdout |
| `OCR_URL` / `VINYL_OCR_URL` | URL für OCR-API; POST mit Bild-Body |
| `VINYL_OCR_IMAGES` | Leerzeichen-getrennte Liste von Bildern für die Pipeline (Cover/Label) |
| `VINYL_CATALOG` | Katalognummer (z.B. 63168), wenn ohne OCR; für 2-Seiten-Modus nötig, falls keine Bilder |
| `VINYL_FETCH_MUSICBRAINZ` | `1` (default) = bei Katalognummer Metadaten von MusicBrainz laden (erster Versuch); `0` = nur OCR |
| `VINYL_USE_SPLEETER` | `1` = nach dem Split Spleeter 2stems pro Track ausführen |
| `OPENCLAW_HOST` | Hostname für Beispiel-Wrapper (z.B. `openclaw`) |
| `REMOTE_OCR_CMD` | OCR-Befehl auf OpenClaw im Beispiel-Wrapper |

## Spleeter (optional)

Spleeter trennt z.B. Gesang und Begleitung (2stems). Nützlich, wenn du pro Track nur die Instrumentals oder nur die Vocals brauchst.

```bash
pip install spleeter
spleeter separate -p spleeter:2stems -o output_dir eingabe.mp3
# → output_dir/eingabe/vocals.wav, accompaniment.wav
```

In dieser Toolchain: `VINYL_USE_SPLEETER=1` in `run_pipeline.sh` erzeugt pro getrenntem Track einen Unterordner mit `vocals.wav` und `accompaniment.wav`.

## Katalognummern und MusicBrainz

Aus dem OCR-Text werden **Katalognummern** erkannt, z.B.:
- **MCA 63168** (Louis Armstrong – 20 Golden Hits)
- **16.21 229-00-1** / **16.21 229-00-2** (Seiten-Nummern auf dem Label)

Ist eine Nummer vorhanden, kann die **Trackliste von MusicBrainz** geladen werden (öffentliche API, Rate-Limit 1 Anfrage/Sekunde):

```bash
# Direkt mit Katalognummer (ohne OCR)
python3 fetch_tracks_by_catalog.py 63168 --json > metadata.json
python3 rename_tracks.py ./ausgabe --meta metadata.json
```

In der Pipeline: Nach dem OCR wird automatisch die erste erkannte Katalognummer für den MusicBrainz-Abruf genutzt; die geladene Trackliste ersetzt dann die aus dem OCR. So erhältst du exakte Titel und Künstler.

## Dateien

| Datei | Beschreibung |
|-------|--------------|
| `split_by_silence.py` | Track-Split per ffmpeg silencedetect |
| `ocr_metadata.py` | OCR aufrufen, Album/Trackliste und Katalognummern parsen |
| `fetch_tracks_by_catalog.py` | Trackliste zu einer Katalognummer von MusicBrainz laden |
| `rename_tracks.py` | Tracks aus Ordner + metadata.json umbenennen und ID3 setzen |
| `run_pipeline.sh` | Kombinierte Pipeline (Split → OCR → ggf. MusicBrainz → Umbenennen → optional Spleeter) |
| `ocr_openclaw.example.sh` | Beispiel-Wrapper für OCR auf OpenClaw (SSH + Remote-Befehl) |
