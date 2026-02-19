# youtube-transcript

Fetch YouTube video transcripts and metadata as JSON via `yt-dlp`.

## Dependencies

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [jq](https://jqlang.github.io/jq/)

## Usage

```bash
# Get transcript with timestamps
youtube-transcript.sh transcript dQw4w9WgXcQ

# Plain text (no timestamps)
youtube-transcript.sh transcript dQw4w9WgXcQ --plain

# Specific language
youtube-transcript.sh transcript dQw4w9WgXcQ --lang es

# Video metadata & available subtitle languages
youtube-transcript.sh info dQw4w9WgXcQ
```

Accepts video IDs or full YouTube URLs. Output is JSON: `{"ok":true,"data":{...}}` on success, `{"ok":false,"error":"..."}` on failure.
