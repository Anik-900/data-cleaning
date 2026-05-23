# Bulk YouTube Subtitle Downloader

A small Python script to download subtitles for many YouTube videos at
once and save them as clean `.txt` files (no timestamps), ready to feed
into NotebookLM, ChatGPT, or any other LLM tool.

## Files

- `nelson_dellis_video_urls.txt` — 310 YouTube URLs, one per line.
- `nelson_dellis_videos_with_titles.txt` — same list with video titles.
- `download_subtitles.py` — the downloader script.

## Setup

```bash
# Python 3.10+ recommended
pip install yt-dlp
```

## Run

Default run — uses `nelson_dellis_video_urls.txt`, English subtitles,
saves into `subtitles/`:

```bash
python download_subtitles.py
```

Custom run:

```bash
python download_subtitles.py \
    --urls my_urls.txt \
    --out my_subs \
    --lang en
```

Each video produces one file named `<title>__<videoId>.txt`. The script
is **resumable** — it skips files that already exist, so you can stop
and re-run anytime.

## "Sign in to confirm you're not a bot" error?

YouTube blocks requests from many cloud / datacenter IPs. If you hit
this error, run the script from your normal home machine, **not** from
a cloud VM / Colab / Codespaces.

If you still see it on your own machine, pass cookies from your
browser:

```bash
# Make sure you're logged into YouTube in Chrome first
python download_subtitles.py --cookies-from-browser chrome
```

Other supported browsers: `firefox`, `edge`, `brave`, `opera`, `safari`,
`chromium`, `vivaldi`.

## Other languages

Use any [ISO language code](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
that the video has captions in, for example:

```bash
python download_subtitles.py --lang bn   # Bengali
python download_subtitles.py --lang es   # Spanish
```

Auto-generated captions count too — the script requests both
human-written and auto-generated tracks.

## Tips for NotebookLM

- **Free plan** allows up to 50 sources per notebook.
- Don't dump all 310 files into one notebook — split by topic
  (memory techniques, competition recaps, interviews, ...).
- Or upgrade to **NotebookLM Plus** for up to 300 sources per notebook.
- You can also paste YouTube URLs directly into NotebookLM and skip
  this whole download step — useful when you only need a handful of
  videos.
