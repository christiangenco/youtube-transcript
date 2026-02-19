#!/usr/bin/env bash
# tools/youtube-transcript.sh
#
# Purpose:
#   Fetch YouTube video transcripts and metadata via yt-dlp.
#   Outputs standard JSON contract: {"ok":true,"data":{...}} or {"ok":false,"error":"..."}
#
# Usage:
#   tools/youtube-transcript.sh transcript <video-id-or-url> [--lang LANG] [--plain]
#   tools/youtube-transcript.sh info <video-id-or-url>
#
# Requires: yt-dlp, jq

set -euo pipefail

# --- Helpers ---

json_ok() {
  jq -nc --argjson data "$1" '{"ok":true,"data":$data}'
}

json_err() {
  jq -nc --arg error "$1" '{"ok":false,"error":$error}'
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  youtube-transcript.sh transcript <video-id-or-url> [--lang LANG] [--plain]
  youtube-transcript.sh info <video-id-or-url>

Commands:
  transcript   Fetch the transcript for a YouTube video
  info         Get video metadata and available subtitle languages

Options (transcript):
  --lang LANG  Subtitle language code (default: en)
  --plain      Output plain text without timestamps
EOF
  exit 1
}

# Extract an 11-char video ID from various URL formats or a bare ID
extract_video_id() {
  local input="$1"
  local vid

  # youtu.be/ID
  if vid=$(echo "$input" | grep -oP '(?<=youtu\.be/)[A-Za-z0-9_-]{11}'); then
    echo "$vid"; return
  fi
  # watch?v=ID or /v/ID or /embed/ID or /shorts/ID
  if vid=$(echo "$input" | grep -oP '(?<=[?&]v=|/v/|/embed/|/shorts/)[A-Za-z0-9_-]{11}'); then
    echo "$vid"; return
  fi
  # bare 11-char ID
  if [[ "$input" =~ ^[A-Za-z0-9_-]{11}$ ]]; then
    echo "$input"; return
  fi

  return 1
}

# --- Commands ---

cmd_info() {
  local input="$1"
  local video_id
  if ! video_id=$(extract_video_id "$input"); then
    json_err "Could not extract video ID from: $input"
  fi

  local meta
  if ! meta=$(yt-dlp --skip-download --print-json --no-warnings -- "$video_id" 2>/dev/null); then
    json_err "yt-dlp failed to fetch video info for: $video_id"
  fi

  local result
  result=$(echo "$meta" | jq -c '{
    video_id: .id,
    title: .title,
    channel: .channel,
    duration: .duration,
    upload_date: (.upload_date | if . then "\(.[0:4])-\(.[4:6])-\(.[6:8])" else null end),
    subtitles: (
      ((.subtitles // {}) | keys) +
      ((.automatic_captions // {}) | keys)
      | unique | sort
    ),
    auto_captions: ((.automatic_captions // {}) | length > 0)
  }')

  json_ok "$result"
}

cmd_transcript() {
  local input="$1"
  shift
  local lang="en"
  local plain=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang) lang="$2"; shift 2 ;;
      --plain) plain=true; shift ;;
      *) json_err "Unknown option: $1" ;;
    esac
  done

  local video_id
  if ! video_id=$(extract_video_id "$input"); then
    json_err "Could not extract video ID from: $input"
  fi

  # Create temp dir, clean up on exit (use /usr/bin/rm to avoid trash wrapper)
  local tmpdir
  tmpdir=$(mktemp -d)
  trap '/usr/bin/rm -rf "$tmpdir" 2>/dev/null || true' EXIT

  # Fetch title separately (--print conflicts with --write-subs)
  local title
  title=$(yt-dlp --skip-download --no-warnings --print "%(title)s" -- "$video_id" 2>/dev/null || echo "")

  # Fetch subtitles (no --print flag so subs actually get written)
  local ytdlp_err
  if ! ytdlp_err=$(yt-dlp \
    --skip-download \
    --no-warnings \
    --write-subs \
    --write-auto-subs \
    --sub-langs "$lang" \
    --sub-format json3 \
    -o "$tmpdir/%(id)s" \
    -- "$video_id" 2>&1 >/dev/null); then
    # Extract the useful part of the error
    local err_msg
    err_msg=$(echo "$ytdlp_err" | grep -oP '(?<=ERROR: ).*' | head -1)
    json_err "yt-dlp failed: ${err_msg:-failed to fetch subtitles for $video_id}"
  fi

  # Find the subtitle file (manual subs preferred over auto)
  local subfile=""
  if [[ -f "$tmpdir/${video_id}.${lang}.json3" ]]; then
    subfile="$tmpdir/${video_id}.${lang}.json3"
  else
    # Auto subs might have varying filename patterns; find any json3 file
    subfile=$(find "$tmpdir" -name "*.json3" -print -quit 2>/dev/null || true)
  fi

  if [[ -z "$subfile" || ! -f "$subfile" ]]; then
    # No subs found — try to report available languages
    local available
    available=$(yt-dlp --skip-download --print-json --no-warnings -- "$video_id" 2>/dev/null | \
      jq -r '(
        ((.subtitles // {}) | keys) +
        ((.automatic_captions // {}) | keys)
      ) | unique | sort | join(", ")' 2>/dev/null || echo "unknown")
    json_err "No subtitles found for language '$lang'. Available: $available"
  fi

  # Parse json3 into transcript text
  local transcript
  if [[ "$plain" == "true" ]]; then
    transcript=$(jq -r '
      [.events[] | select(.segs) | [.segs[].utf8 // ""] | join("")]
      | join(" ")
      | gsub("\n"; " ")
      | gsub("  +"; " ")
      | ltrimstr(" ") | rtrimstr(" ")
    ' < "$subfile")
  else
    transcript=$(jq -r '
      .events[] | select(.segs) |
      "[" + (
        ((.tStartMs / 1000) | floor) as $t |
        (($t / 60) | floor | tostring) + ":" +
        (($t % 60) | tostring | if length == 1 then "0" + . else . end)
      ) + "] " +
      ([.segs[].utf8 // ""] | join("") | gsub("\n"; " ") | gsub("^ +| +$"; ""))
    ' < "$subfile")
  fi

  # Build result JSON
  local result
  result=$(jq -nc \
    --arg video_id "$video_id" \
    --arg title "$title" \
    --arg lang "$lang" \
    --arg transcript "$transcript" \
    '{video_id: $video_id, title: $title, lang: $lang, transcript: $transcript}')

  json_ok "$result"
}

# --- Main ---

if [[ $# -lt 2 ]]; then
  usage
fi

command="$1"
shift

case "$command" in
  transcript) cmd_transcript "$@" ;;
  info)       cmd_info "$1" ;;
  *)          usage ;;
esac
