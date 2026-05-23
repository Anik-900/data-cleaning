"""
Bulk YouTube subtitle downloader.

Reads a list of YouTube video URLs (one per line) and downloads
subtitles for each into an output directory as plain `.txt` files
(timestamps and tags stripped). Files are ready to feed into
NotebookLM, ChatGPT, etc.

Features:
    - Prefers human-written subtitles, falls back to auto-generated
    - Skips videos whose subtitle file already exists (resumable)
    - Optional cookie support to bypass "Sign in to confirm you're
      not a bot" errors

Requirements:
    pip install yt-dlp

Usage:
    python download_subtitles.py
    python download_subtitles.py --urls my_urls.txt --out subs --lang en
    python download_subtitles.py --cookies-from-browser chrome
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


def sanitize(name: str) -> str:
    """Make a string safe to use as a filename."""
    name = re.sub(r"[^\w\-. ]", "_", name)
    return name.strip()[:120] or "video"


def vtt_to_plain_text(vtt: str) -> str:
    """Strip WEBVTT headers, timestamps, and tags. Keep unique lines in order."""
    lines: list[str] = []
    seen: set[str] = set()
    for raw in vtt.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE")):
            continue
        if "-->" in line:
            continue
        if re.match(r"^\d+$", line):  # cue numbers
            continue
        # remove inline tags like <c> and timestamp tags
        line = re.sub(r"<[^>]+>", "", line)
        if line and line not in seen:
            seen.add(line)
            lines.append(line)
    return "\n".join(lines)


def build_extra_args(args: argparse.Namespace) -> list[str]:
    """Build extra yt-dlp arguments for cookies/proxy/etc."""
    extra: list[str] = []
    if args.cookies_from_browser:
        extra += ["--cookies-from-browser", args.cookies_from_browser]
    if args.cookies:
        extra += ["--cookies", args.cookies]
    if args.proxy:
        extra += ["--proxy", args.proxy]
    return extra


def get_metadata(url: str, extra: list[str]) -> tuple[str, str]:
    """Return (video_id, title) using yt-dlp."""
    result = subprocess.run(
        ["yt-dlp", *extra, "--print", "%(id)s\t%(title)s", "--skip-download", url],
        capture_output=True, text=True, check=True,
    )
    vid, title = result.stdout.strip().split("\t", 1)
    return vid, title


def download_subtitle(
    url: str, out_dir: Path, lang: str, extra: list[str]
) -> Path | None:
    """Download subtitles for one video. Returns path to saved .txt or None."""
    vid, title = get_metadata(url, extra)
    safe_title = sanitize(title)
    out_path = out_dir / f"{safe_title}__{vid}.txt"

    if out_path.exists() and out_path.stat().st_size > 0:
        print(f"  skip (exists): {out_path.name}")
        return out_path

    tmp_template = str(out_dir / f"{vid}.%(ext)s")
    cmd = [
        "yt-dlp", *extra,
        "--skip-download",
        "--write-subs",
        "--write-auto-subs",
        "--sub-lang", lang,
        "--sub-format", "vtt",
        "--convert-subs", "vtt",
        "-o", tmp_template,
        url,
    ]
    subprocess.run(cmd, capture_output=True, text=True, check=False)

    # find the produced .vtt
    vtt_files = list(out_dir.glob(f"{vid}*.vtt"))
    if not vtt_files:
        print(f"  no subtitles for {vid} ({title!r})")
        return None

    vtt_text = vtt_files[0].read_text(encoding="utf-8", errors="ignore")
    plain = vtt_to_plain_text(vtt_text)
    out_path.write_text(plain, encoding="utf-8")

    # cleanup raw .vtt files
    for f in vtt_files:
        f.unlink(missing_ok=True)

    print(f"  saved: {out_path.name}  ({len(plain):,} chars)")
    return out_path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--urls", default="nelson_dellis_video_urls.txt",
                   help="Text file with one YouTube URL per line.")
    p.add_argument("--out", default="subtitles",
                   help="Directory to save subtitle .txt files.")
    p.add_argument("--lang", default="en",
                   help="Subtitle language code (en, bn, es, ...).")
    p.add_argument("--cookies-from-browser", default=None,
                   help="Browser to read cookies from (chrome, firefox, ...).")
    p.add_argument("--cookies", default=None,
                   help="Path to a cookies.txt file.")
    p.add_argument("--proxy", default=None,
                   help="Proxy URL, e.g. http://user:pass@host:port")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    url_file = Path(args.urls)
    out_dir = Path(args.out)

    if not url_file.exists():
        print(f"URL file not found: {url_file}", file=sys.stderr)
        return 1

    out_dir.mkdir(exist_ok=True)
    extra = build_extra_args(args)

    urls = [u.strip() for u in url_file.read_text().splitlines() if u.strip()]
    print(f"Downloading {args.lang} subtitles for {len(urls)} videos -> {out_dir}/\n")

    ok = fail = 0
    for i, url in enumerate(urls, 1):
        print(f"[{i}/{len(urls)}] {url}")
        try:
            if download_subtitle(url, out_dir, args.lang, extra):
                ok += 1
            else:
                fail += 1
        except Exception as e:  # noqa: BLE001
            print(f"  error: {e}")
            fail += 1

    print(f"\nDone. success={ok}  failed/no-subs={fail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
