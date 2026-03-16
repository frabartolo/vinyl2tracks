#!/bin/bash
# Pipeline: Schallplatten-Rip → Tracks aufteilen (eine oder beide Seiten) → Metadaten (OCR + MusicBrainz) → Umbenennen/Taggen
#
# Verwendung:
#   Eine Seite:  ./run_pipeline.sh <eingabe.mp3> [ausgabe_ordner]
#   Beide Seiten in ein Verzeichnis:
#     ./run_pipeline.sh <seite_a.mp3> <seite_b.mp3> [ausgabe_ordner]
#     (Metadaten zuerst: OCR und/oder VINYL_CATALOG für MusicBrainz nötig, damit Trackanzahl pro Seite bekannt ist)
#   Mit OCR/Bildern:  VINYL_OCR_IMAGES="cover.jpg label.jpg" OCR_CMD=... ./run_pipeline.sh ...
#   Nur Katalognummer (ohne OCR):  VINYL_CATALOG=63168 ./run_pipeline.sh seite_a.mp3 seite_b.mp3 ./ausgabe

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT1="${1:?Usage: $0 <eingabe.mp3> [eingabe2.mp3] [ausgabe_ordner]}"
INPUT2=""
OUT_DIR=""
if [ -n "$2" ] && [ -f "$2" ]; then
  INPUT2="$2"
  OUT_DIR="${3:-}"
else
  OUT_DIR="${2:-}"
fi
if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(dirname "$INPUT1")/$(basename "$INPUT1" | sed 's/\.[^.]*$//')_tracks"
  [ -n "$INPUT2" ] && OUT_DIR="$(dirname "$INPUT1")/album_tracks"
fi
mkdir -p "$OUT_DIR"

OCR_IMAGES="${VINYL_OCR_IMAGES:-}"
USE_SPLEETER="${VINYL_USE_SPLEETER:-0}"
VINYL_CATALOG="${VINYL_CATALOG:-}"

# === Schritt 0: Metadaten zuerst (bei 2 Seiten nötig; bei 1 Seite optional, aber MusicBrainz als erster Versuch)
# So wissen wir die Gesamt-Trackliste und ggf. tracks_per_medium (Seiten)
get_metadata() {
  if [ -n "$OCR_IMAGES" ] && { [ -n "${OCR_CMD}" ] || [ -n "${VINYL_OCR_CMD}" ] || [ -n "${OCR_URL}" ]; }; then
    python3 "$SCRIPT_DIR/ocr_metadata.py" $OCR_IMAGES --json > "$OUT_DIR/metadata_ocr.json" 2>/dev/null || true
    [ -f "$OUT_DIR/metadata_ocr.json" ] && CATALOG=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); c=d.get('catalog_numbers',[]); print(c[0] if c else '')" "$OUT_DIR/metadata_ocr.json" 2>/dev/null)
  fi
  [ -z "$CATALOG" ] && [ -n "$VINYL_CATALOG" ] && CATALOG="$VINYL_CATALOG"
  if [ -n "$CATALOG" ] && [ "${VINYL_FETCH_MUSICBRAINZ:-1}" = "1" ]; then
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
      echo "Bei 2 Seiten werden Metadaten benötigt. Setze VINYL_OCR_IMAGES oder VINYL_CATALOG." >&2
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
if [ -z "$INPUT2" ] && [ -n "$OCR_IMAGES" ] && { [ -n "${OCR_CMD}" ] || [ -n "${VINYL_OCR_CMD}" ] || [ -n "${OCR_URL}" ]; }; then
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
