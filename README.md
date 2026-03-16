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

Alle Parameter werden als **Kommandozeilen-Optionen** übergeben (Umgebungsvariablen optional als Fallback):

```bash
# Eine Seite
./run_pipeline.sh /pfad/zu/seite_a.mp3 [ausgabe_ordner]

# Beide Seiten → ein Verzeichnis, mit Katalognummer (MusicBrainz als erster Versuch)
./run_pipeline.sh -c 63168 seite_a.mp3 seite_b.mp3 ./ausgabe

# Oder: Katalognummer in vinyl2tracks.txt im Aufnahme-Ordner ablegen, dann ohne -c:
./run_pipeline.sh seite_a.mp3 seite_b.mp3 ./ausgabe

# Ohne Nachfrage (z.B. für Skripte): Umbenennen/Taggen direkt ausführen
./run_pipeline.sh -y -c 63168 seite_a.mp3 seite_b.mp3 ./ausgabe

# Mit OCR-Bildern (Cover/Label) und optional OCR-Befehl
./run_pipeline.sh -i cover.jpg label.jpg --ocr-cmd /pfad/zu/ocr.sh seite_a.mp3 seite_b.mp3 ./ausgabe

# Katalognummer + Spleeter nach dem Split
./run_pipeline.sh -c 63168 --spleeter seite_a.mp3 seite_b.mp3 ./ausgabe

# Hilfe zu allen Optionen
./run_pipeline.sh --help
```

**Optionen:** `-i, --images`, `-c, --catalog`, `--ocr-cmd`, `--config DATEI`, `--spleeter`, `--no-musicbrainz`, `-y, --yes` (Umbenennen ohne Nachfrage), `-h, --help`.

Die Pipeline lädt bei angegebener Katalognummer (**-c**) **zuerst** die Metadaten von MusicBrainz. Anschließend werden beide Seiten in ein gemeinsames Verzeichnis geschnitten und alle Infos in die MP3-Tags übernommen.

## Konfiguration

**Reihenfolge:** Kommandozeile → **lokale Datei** (im Aufnahme-Ordner) → Config-Datei → Umgebungsvariablen.

**Lokale Datei im Aufnahme-Verzeichnis:** Lege im **selben Ordner** wie deine Aufnahmen (z. B. neben `seite_a.mp3` / `seite_b.mp3`) eine Datei **`vinyl2tracks.txt`** an. Darin z. B. die Katalognummer für genau diese Platte:

```ini
# vinyl2tracks.txt (im Ordner der Schallplatten-Aufnahme)
catalog = 63168
```

Erlaubte Keys wie in der Config-Datei: `catalog`, `images`, `ocr_cmd`, `musicbrainz`, `spleeter`. So brauchst du `-c 63168` nicht jedes Mal anzugeben, wenn du aus diesem Ordner startest.

**Config-Datei (statische Parameter):** Lege `vinyl2tracks.conf` im Projektverzeichnis oder unter `~/.config/vinyl2tracks.conf` an (oder gib sie mit `--config DATEI` an). Format: `key = value`, Zeilen mit `#` sind Kommentare.

```ini
# vinyl2tracks.conf
ocr_cmd = /pfad/zu/ocr_openclaw.sh
catalog = 63168
images = cover.jpg label.jpg
musicbrainz = 1
spleeter = 0
```

Siehe `vinyl2tracks.conf.example`. Erlaubte Keys: `ocr_cmd`, `catalog`, `images`, `musicbrainz`, `spleeter`, `rename_confirm` (0 = Umbenennen ohne Nachfrage).

**Kommandozeile:** Siehe `./run_pipeline.sh --help`.

**Umgebungsvariablen (optionaler Fallback):**

| Variable | Bedeutung |
|----------|-----------|
| `OCR_CMD` / `VINYL_OCR_CMD` | OCR-Befehl (sonst per `--ocr-cmd`) |
| `OCR_URL` / `VINYL_OCR_URL` | URL für OCR-API; POST mit Bild-Body |
| `VINYL_OCR_IMAGES` | Bilder für OCR (sonst per `-i/--images`) |
| `VINYL_CATALOG` | Katalognummer (sonst per `-c/--catalog`) |
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
| `vinyl2tracks.conf.example` | Beispiel-Config für statische Parameter (ocr_cmd, catalog, …) |
| `vinyl2tracks.txt.example` | Beispiel für lokale Datei im Aufnahme-Ordner (z. B. nur `catalog = 63168`) |
| `ocr_openclaw.example.sh` | Beispiel-Wrapper für OCR auf OpenClaw (SSH + Remote-Befehl) |
