# youtube-transcript

```
youtube-transcript.sh transcript <video-id-or-url> [--lang LANG] [--plain]
youtube-transcript.sh info <video-id-or-url>
```

## transcript

Fetch subtitle transcript. Returns JSON with `video_id`, `title`, `lang`, `transcript`.

| Flag | Default | Description |
|------|---------|-------------|
| `--lang LANG` | `en` | Subtitle language code |
| `--plain` | off | Plain text without timestamps |

```bash
youtube-transcript.sh transcript dQw4w9WgXcQ
youtube-transcript.sh transcript "https://youtu.be/dQw4w9WgXcQ" --lang es --plain
```

## info

Get video metadata and available subtitle languages. Returns JSON with `video_id`, `title`, `channel`, `duration`, `upload_date`, `subtitles`, `auto_captions`.

```bash
youtube-transcript.sh info dQw4w9WgXcQ
```
