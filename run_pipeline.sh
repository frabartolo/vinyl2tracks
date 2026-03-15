#!/bin/bash
# Pipeline: Schallplatten-Rip → Tracks aufteilen → optional OCR-Metadaten → optional Spleeter
#
# 1. Eine lange MP3/WAV pro Seite (oder ganze Platte) mit split_by_silence.py in Tracks zerlegen
# 2. Optional: Bilder (Cover/Label) mit ocr_metadata.py auswerten → JSON
# 3. Optional: Tracks nach OCR umbenennen und taggen (rename_tracks.py)
# 4. Optional: Spleeter (Stem-Separation, z.B. nur Begleitung behalten) – siehe README
#
# Verwendung:
#   ./run_pipeline.sh <eingabe.mp3> [ausgabe_ordner]
#   VINYL_OCR_IMAGES="cover.jpg label.jpg" ./run_pipeline.sh <eingabe.mp3>
#   VINYL_USE_SPLEETER=1 ./run_pipeline.sh <eingabe.mp3>   # optional, langsam

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="${1:?Usage: $0 <eingabe.mp3> [ausgabe_ordner]}"
OUT_DIR="${2:-}"
OCR_IMAGES="${VINYL_OCR_IMAGES:-}"
USE_SPLEETER="${VINYL_USE_SPLEETER:-0}"

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(dirname "$INPUT")/$(basename "$INPUT" | sed 's/\.[^.]*$//')_tracks"
fi
mkdir -p "$OUT_DIR"

echo "=== 1. Track-Split (Stille-Erkennung) ==="
python3 "$SCRIPT_DIR/split_by_silence.py" "$INPUT" -o "$OUT_DIR" --format mp3
echo ""

if [ -n "$OCR_IMAGES" ]; then
  echo "=== 2. OCR-Metadaten (Cover/Label) + ggf. MusicBrainz ==="
  if [ -n "${OCR_CMD}" ] || [ -n "${VINYL_OCR_CMD}" ] || [ -n "${OCR_URL}" ]; then
    python3 "$SCRIPT_DIR/ocr_metadata.py" $OCR_IMAGES --json > "$OUT_DIR/metadata_ocr.json" || true
    if [ -f "$OUT_DIR/metadata_ocr.json" ]; then
      # Wenn Katalognummer erkannt: Trackliste von MusicBrainz laden (öffentliche API)
      CATALOG=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); c=d.get('catalog_numbers',[]); print(c[0] if c else '')" "$OUT_DIR/metadata_ocr.json" 2>/dev/null)
      if [ -n "$CATALOG" ] && [ "${VINYL_FETCH_MUSICBRAINZ:-1}" = "1" ]; then
        echo "Katalognummer erkannt: $CATALOG – lade Trackliste von MusicBrainz …"
        if python3 "$SCRIPT_DIR/fetch_tracks_by_catalog.py" "$CATALOG" --json > "$OUT_DIR/metadata_mb.json" 2>/dev/null; then
          # MusicBrainz-JSON hat album, artist, tracks – für rename_tracks reicht das
          cp "$OUT_DIR/metadata_mb.json" "$OUT_DIR/metadata.json"
          echo "Trackliste von MusicBrainz übernommen."
        else
          cp "$OUT_DIR/metadata_ocr.json" "$OUT_DIR/metadata.json"
        fi
      else
        cp "$OUT_DIR/metadata_ocr.json" "$OUT_DIR/metadata.json"
      fi
    fi
    if [ -f "$OUT_DIR/metadata.json" ]; then
      python3 "$SCRIPT_DIR/rename_tracks.py" "$OUT_DIR" --meta "$OUT_DIR/metadata.json" --dry-run
      if [ -t 0 ]; then
        read -r -p "Tracks wie oben umbenennen und taggen? [jN] " ans
        if [ "$ans" = "j" ] || [ "$ans" = "J" ]; then
          python3 "$SCRIPT_DIR/rename_tracks.py" "$OUT_DIR" --meta "$OUT_DIR/metadata.json"
        fi
      fi
    fi
  else
    echo "OCR nicht konfiguriert (OCR_CMD oder OCR_URL). Überspringe."
  fi
  echo ""
fi

if [ "$USE_SPLEETER" = "1" ]; then
  echo "=== 3. Optional: Spleeter (2stems: vocals + accompaniment) ==="
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
fi

echo "Fertig. Ausgabe: $OUT_DIR"
