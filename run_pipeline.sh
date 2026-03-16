#!/bin/bash
# Pipeline: Schallplatten-Rip → Tracks aufteilen (eine oder beide Seiten) → Metadaten (OCR + MusicBrainz) → Umbenennen/Taggen
#
# Verwendung:
#   ./run_pipeline.sh [OPTIONEN] <eingabe.mp3> [eingabe2.mp3] [ausgabe_ordner]
#
# Optionen:
#   -i, --images DATEI [DATEI ...]   Bilder für OCR (Cover/Label)
#   -c, --catalog NUMMER             Katalognummer (z.B. 63168) für MusicBrainz
#   --ocr-cmd BEFEHL                 OCR-Befehl (erhält Bildpfad, liefert Text auf stdout)
#   --config DATEI                   Config-Datei (Standard: ./vinyl2tracks.conf, ~/.config/vinyl2tracks.conf)
#   --spleeter                       Nach dem Split Spleeter 2stems ausführen
#   --no-musicbrainz                 MusicBrainz-Abruf weglassen (nur OCR)
#   -h, --help                       Diese Hilfe anzeigen
#
# Config-Datei: key = value (ocr_cmd, catalog, images, musicbrainz, spleeter). Siehe vinyl2tracks.conf.example.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults: zuerst Umgebung, dann werden Config und CLI angewendet
DEFAULT_OCR_IMAGES="${VINYL_OCR_IMAGES:-}"
DEFAULT_CATALOG="${VINYL_CATALOG:-}"
OCR_IMAGES=""
VINYL_CATALOG=""
USE_SPLEETER=0
FETCH_MUSICBRAINZ=1
OCR_CMD_ARG=""
CONFIG_FILE=""
CONFIG_ocr_cmd=""
CONFIG_catalog=""
CONFIG_images=""
CONFIG_spleeter=""
CONFIG_musicbrainz=""

read_config_file() {
  local f="$1"
  [[ ! -r "$f" ]] && return
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      case "$key" in
        ocr_cmd)     CONFIG_ocr_cmd="$val" ;;
        catalog)     CONFIG_catalog="$val" ;;
        images)      CONFIG_images="$val" ;;
        spleeter)    CONFIG_spleeter="$val" ;;
        musicbrainz) CONFIG_musicbrainz="$val" ;;
      esac
    fi
  done < "$f"
}

show_usage() {
  echo "Verwendung: $0 [OPTIONEN] <eingabe.mp3> [eingabe2.mp3] [ausgabe_ordner]"
  echo ""
  echo "Optionen:"
  echo "  -i, --images DATEI [DATEI ...]   Bilder für OCR (Cover/Label)"
  echo "  -c, --catalog NUMMER             Katalognummer für MusicBrainz (z.B. 63168)"
  echo "  --ocr-cmd BEFEHL                  OCR-Befehl (erhält Bildpfad, stdout = Text)"
  echo "  --config DATEI                   Config-Datei (Standard: ./vinyl2tracks.conf, ~/.config/vinyl2tracks.conf)"
  echo "  --spleeter                       Nach dem Split Spleeter 2stems ausführen"
  echo "  --no-musicbrainz                 Kein MusicBrainz-Abruf (nur OCR)"
  echo "  -h, --help                       Diese Hilfe"
  echo ""
  echo "Config-Datei: key = value, z.B. ocr_cmd = /pfad/ocr.sh  (siehe vinyl2tracks.conf.example)"
  echo ""
  echo "Beispiele:"
  echo "  $0 -c 63168 seite_a.mp3 seite_b.mp3 ./ausgabe"
  echo "  $0 --config ~/.config/vinyl2tracks.conf seite_a.mp3 seite_b.mp3 ./ausgabe"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--images)
      shift
      while [[ $# -gt 0 && $1 != -* ]]; do OCR_IMAGES="$OCR_IMAGES $1"; shift; done
      ;;
    -c|--catalog)   VINYL_CATALOG="$2"; shift 2 ;;
    --ocr-cmd)     OCR_CMD_ARG="$2"; shift 2 ;;
    --config)      CONFIG_FILE="$2"; shift 2 ;;
    --spleeter)    USE_SPLEETER=1; shift ;;
    --no-musicbrainz) FETCH_MUSICBRAINZ=0; shift ;;
    -h|--help)     show_usage; exit 0 ;;
    *) break ;;
  esac
done
OCR_IMAGES="${OCR_IMAGES# }"

# Config-Datei lesen (explizit angegeben oder Standardorte)
if [[ -n "$CONFIG_FILE" ]]; then
  read_config_file "$CONFIG_FILE"
else
  [[ -r "$SCRIPT_DIR/vinyl2tracks.conf" ]] && read_config_file "$SCRIPT_DIR/vinyl2tracks.conf"
  [[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/vinyl2tracks.conf" ]] && read_config_file "${XDG_CONFIG_HOME:-$HOME/.config}/vinyl2tracks.conf"
fi

# Fallback: zuerst Config, dann Umgebung
[[ -z "$OCR_IMAGES" && -n "$CONFIG_images" ]] && OCR_IMAGES="$CONFIG_images"
[[ -z "$OCR_IMAGES" && -n "$DEFAULT_OCR_IMAGES" ]] && OCR_IMAGES="$DEFAULT_OCR_IMAGES"
[[ -z "$VINYL_CATALOG" && -n "$CONFIG_catalog" ]] && VINYL_CATALOG="$CONFIG_catalog"
[[ -z "$VINYL_CATALOG" && -n "$DEFAULT_CATALOG" ]] && VINYL_CATALOG="$DEFAULT_CATALOG"
[[ -z "$OCR_CMD_ARG" && -n "$CONFIG_ocr_cmd" ]] && OCR_CMD_ARG="$CONFIG_ocr_cmd"
[[ "$USE_SPLEETER" -eq 0 && "$CONFIG_spleeter" = "1" ]] && USE_SPLEETER=1
[[ "$FETCH_MUSICBRAINZ" -eq 1 && "$CONFIG_musicbrainz" = "0" ]] && FETCH_MUSICBRAINZ=0
[[ -n "$OCR_CMD_ARG" ]] && export OCR_CMD="$OCR_CMD_ARG"

# Positionale Argumente: Eingabe1 [Eingabe2] [Ausgabe]
[[ $# -eq 0 ]] && echo "Fehler: Mindestens eine Eingabedatei angeben." >&2 && show_usage >&2 && exit 1
INPUT1="$1"
INPUT2=""
OUT_DIR=""
shift
if [[ $# -gt 0 && -f "$1" ]]; then
  INPUT2="$1"
  shift
  OUT_DIR="${1:-}"
  [[ $# -gt 0 ]] && shift
else
  OUT_DIR="$1"
  [[ $# -gt 0 ]] && shift
fi
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$(dirname "$INPUT1")/$(basename "$INPUT1" | sed 's/\.[^.]*$//')_tracks"
  [[ -n "$INPUT2" ]] && OUT_DIR="$(dirname "$INPUT1")/album_tracks"
fi
mkdir -p "$OUT_DIR"

# === Schritt 0: Metadaten zuerst (bei 2 Seiten nötig; bei 1 Seite optional, aber MusicBrainz als erster Versuch)
# So wissen wir die Gesamt-Trackliste und ggf. tracks_per_medium (Seiten)
get_metadata() {
  if [ -n "$OCR_IMAGES" ] && { [ -n "${OCR_CMD:-}" ] || [ -n "${VINYL_OCR_CMD:-}" ] || [ -n "${OCR_URL:-}" ]; }; then
    python3 "$SCRIPT_DIR/ocr_metadata.py" $OCR_IMAGES --json > "$OUT_DIR/metadata_ocr.json" 2>/dev/null || true
    [ -f "$OUT_DIR/metadata_ocr.json" ] && CATALOG=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); c=d.get('catalog_numbers',[]); print(c[0] if c else '')" "$OUT_DIR/metadata_ocr.json" 2>/dev/null)
  fi
  [ -z "$CATALOG" ] && [ -n "$VINYL_CATALOG" ] && CATALOG="$VINYL_CATALOG"
  if [ -n "$CATALOG" ] && [ "$FETCH_MUSICBRAINZ" = "1" ]; then
    echo "Katalognummer: $CATALOG – lade Metadaten von MusicBrainz (erster Versuch) …"
    if python3 "$SCRIPT_DIR/fetch_tracks_by_catalog.py" "$CATALOG" --json > "$OUT_DIR/metadata.json" 2>/dev/null; then
      echo "Metadaten von MusicBrainz übernommen."
      return 0
    fi
  fi
  if [ -f "$OUT_DIR/metadata_ocr.json" ]; then
    cp "$OUT_DIR/metadata_ocr.json" "$OUT_DIR/metadata.json"
    return 0
  fi
  return 1
}

if [ -n "$INPUT2" ] || [ -n "$OCR_IMAGES" ] || [ -n "$VINYL_CATALOG" ]; then
  echo "=== 0. Metadaten (OCR + MusicBrainz) ==="
  if ! get_metadata; then
    if [ -n "$INPUT2" ]; then
      echo "Bei 2 Seiten werden Metadaten benötigt. Option -c/--catalog oder -i/--images (mit --ocr-cmd) angeben." >&2
      exit 1
    fi
  fi
  echo ""
fi

# === Schritt 1: Track-Split ===
if [ -n "$INPUT2" ]; then
  # Beide Seiten in ein Verzeichnis
  if [ ! -f "$OUT_DIR/metadata.json" ]; then
    echo "Keine metadata.json – Abbruch." >&2
    exit 1
  fi
  TOTAL=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('tracks',[])))" "$OUT_DIR/metadata.json" 2>/dev/null || echo "0")
  PER_MEDIUM=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); m=d.get('tracks_per_medium',[]); print(' '.join(map(str,m)))" "$OUT_DIR/metadata.json" 2>/dev/null || echo "")
  if [ -n "$PER_MEDIUM" ]; then
    N1=$(echo "$PER_MEDIUM" | awk '{print $1}')
    N2=$(echo "$PER_MEDIUM" | awk '{print $2}')
  fi
  if [ -z "$N1" ] || [ -z "$N2" ]; then
    N1=$((TOTAL / 2))
    N2=$((TOTAL - N1))
  fi
  echo "=== 1. Track-Split (Seite A: $N1, Seite B: $N2 Tracks) ==="
  python3 "$SCRIPT_DIR/split_by_silence.py" "$INPUT1" -o "$OUT_DIR" -n "$N1" --format mp3
  python3 "$SCRIPT_DIR/split_by_silence.py" "$INPUT2" -o "$OUT_DIR" -n "$N2" --format mp3 --track-offset "$N1"
else
  echo "=== 1. Track-Split (Stille-Erkennung) ==="
  N_ARG=""
  if [ -f "$OUT_DIR/metadata.json" ]; then
    N=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get('tracks',[])))" "$OUT_DIR/metadata.json" 2>/dev/null || echo "")
    [ -n "$N" ] && [ "$N" -gt 0 ] && N_ARG="-n $N"
  fi
  python3 "$SCRIPT_DIR/split_by_silence.py" "$INPUT1" -o "$OUT_DIR" --format mp3 $N_ARG
fi
echo ""

# === Schritt 2: Metadaten (falls noch nicht) + Umbenennen/Taggen ===
if [ -z "$INPUT2" ] && [ -n "$OCR_IMAGES" ] && { [ -n "${OCR_CMD:-}" ] || [ -n "${VINYL_OCR_CMD:-}" ] || [ -n "${OCR_URL:-}" ]; }; then
  if [ ! -f "$OUT_DIR/metadata.json" ]; then
    echo "=== 2. OCR + MusicBrainz ==="
    get_metadata || true
    echo ""
  fi
fi
if [ -f "$OUT_DIR/metadata.json" ]; then
  echo "=== 2. Umbenennen & Taggen ==="
  python3 "$SCRIPT_DIR/rename_tracks.py" "$OUT_DIR" --meta "$OUT_DIR/metadata.json" --dry-run
  if [ -t 0 ]; then
    read -r -p "Tracks wie oben umbenennen und taggen? [jN] " ans
    if [ "$ans" = "j" ] || [ "$ans" = "J" ]; then
      python3 "$SCRIPT_DIR/rename_tracks.py" "$OUT_DIR" --meta "$OUT_DIR/metadata.json"
    fi
  fi
  echo ""
fi

# === Schritt 3: Optional Spleeter ===
if [ "$USE_SPLEETER" = "1" ]; then
  echo "=== 3. Optional: Spleeter (2stems) ==="
  if command -v spleeter >/dev/null 2>&1; then
    SPLEETER_OUT="$OUT_DIR/spleeter_2stems"
    mkdir -p "$SPLEETER_OUT"
    for f in "$OUT_DIR"/*.mp3; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .mp3)
      spleeter separate -p spleeter:2stems -o "$SPLEETER_OUT" "$f"
      echo "  $f → $SPLEETER_OUT/$base/"
    done
  else
    echo "Spleeter nicht installiert. pip install spleeter (optional)."
  fi
  echo ""
fi

echo "Fertig. Ausgabe: $OUT_DIR"
