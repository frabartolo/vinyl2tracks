#!/usr/bin/env python3
"""Trackliste zu einer Katalognummer von MusicBrainz laden.

Verwendet die öffentliche MusicBrainz-API (kein API-Key nötig).
Rate-Limit: max. 1 Anfrage/Sekunde; sinnvoller User-Agent erforderlich.

Beispiele für Katalognummern: MCA 63168, 63168, 16.21 229-00-1
"""

import argparse
import json
import re
import sys
import time
from typing import Any, Dict, List, Optional

try:
    import urllib.request
    import urllib.parse
    import urllib.error
except ImportError:
    urllib = None  # type: ignore

USER_AGENT = "vinyl2tracks/1.0 (https://github.com/frabartolo/vinyl2tracks)"
MB_SEARCH = "https://musicbrainz.org/ws/2/release/"
MB_LOOKUP = "https://musicbrainz.org/ws/2/release/"


def _request(url: str, headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def search_release_by_catalog(catalog_number: str, limit: int = 5) -> List[Dict[str, Any]]:
    """MusicBrainz: Release-Suche nach Katalognummer. Liefert Liste von Treffern."""
    # catno ist case/space-insensitiv; Sonderzeichen escapen
    catno_clean = re.sub(r"[\s]+", " ", catalog_number.strip())
    query = urllib.parse.quote(f'catno:"{catno_clean}"')
    url = f"{MB_SEARCH}?query={query}&fmt=json&limit={limit}"
    data = _request(url)
    time.sleep(1.05)  # Rate-Limit vor nächster Anfrage
    return data.get("releases") or []


def get_release_with_tracks(release_id: str) -> Optional[Dict[str, Any]]:
    """Einzelnen Release inkl. Medien/Tracks abrufen."""
    url = f"{MB_LOOKUP}{release_id}?inc=recordings+artist-credits&fmt=json"
    time.sleep(1.05)  # Rate-Limit mind. 1/s
    data = _request(url)
    return data


def extract_tracklist(release: Dict[str, Any]) -> List[str]:
    """Aus Release-JSON die Tracktitel in Reihenfolge extrahieren."""
    tracks: List[str] = []
    media_list = release.get("media") or []
    for medium in media_list:
        # API liefert "tracks" (nicht "track")
        for track in medium.get("tracks") or medium.get("track") or []:
            title = (track.get("title") or "").strip()
            if not title and track.get("recording"):
                title = (track["recording"].get("title") or "").strip()
            if title:
                tracks.append(title)
    return tracks


def fetch_metadata_by_catalog(
    catalog_number: str,
    prefer_medium: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """
    Katalognummer bei MusicBrainz suchen und Metadaten + Trackliste liefern.
    prefer_medium: 1-based Medium-Index (z.B. 1 = Seite A), None = alle Tracks.
    """
    if not catalog_number or not catalog_number.strip():
        return None
    catalog_number = catalog_number.strip()
    releases = search_release_by_catalog(catalog_number, limit=5)
    if not releases:
        return None
    # Ersten Treffer mit Tracks abrufen
    release_id = releases[0].get("id")
    if not release_id:
        return None
    release = get_release_with_tracks(release_id)
    if not release:
        return None
    tracks = extract_tracklist(release)
    if not tracks and (release.get("media") or []):
        # Fallback: recording title aus track
        for medium in release.get("media") or []:
            for track in medium.get("tracks") or medium.get("track") or []:
                rec = track.get("recording")
                if rec and rec.get("title"):
                    tracks.append(rec["title"].strip())
    artist_credit = (release.get("artist-credit") or [])
    artist_name = ""
    for ac in artist_credit:
        if isinstance(ac, dict) and ac.get("artist", {}).get("name"):
            artist_name = ac["artist"]["name"]
            break
        if isinstance(ac, str):
            artist_name = ac
            break
    title = (release.get("title") or "").strip()
    return {
        "album": title or "Unbekannt",
        "artist": artist_name or "",
        "tracks": tracks,
        "catalog_number": catalog_number,
        "musicbrainz_release_id": release.get("id"),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Trackliste zu einer Katalognummer von MusicBrainz laden"
    )
    parser.add_argument(
        "catalog",
        nargs="?",
        default=None,
        help="Katalognummer (z.B. 63168, MCA 63168, 16.21 229-00-1)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Nur JSON ausgeben (album, artist, tracks)",
    )
    parser.add_argument(
        "--medium",
        type=int,
        default=None,
        metavar="N",
        help="Nur Medium N (1-basiert, z.B. 1 für Seite A) verwenden",
    )
    args = parser.parse_args()
    catalog = args.catalog
    if not catalog and not sys.stdin.isatty():
        catalog = sys.stdin.read().strip()
    if not catalog:
        print("Keine Katalognummer angegeben.", file=sys.stderr)
        sys.exit(1)
    if urllib is None:
        print("urllib nicht verfügbar.", file=sys.stderr)
        sys.exit(1)
    try:
        meta = fetch_metadata_by_catalog(catalog, prefer_medium=args.medium)
    except Exception as e:
        print(f"MusicBrainz-Anfrage fehlgeschlagen: {e}", file=sys.stderr)
        sys.exit(1)
    if not meta or not meta.get("tracks"):
        print("Kein Release oder keine Tracks gefunden.", file=sys.stderr)
        sys.exit(1)
    if args.json:
        out = {k: meta[k] for k in ("album", "artist", "tracks") if k in meta}
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return
    print("Album:", meta.get("album", ""))
    print("Artist:", meta.get("artist", ""))
    print("Tracks:")
    for i, t in enumerate(meta.get("tracks") or [], 1):
        print(f"  {i:2d}. {t}")


if __name__ == "__main__":
    main()
