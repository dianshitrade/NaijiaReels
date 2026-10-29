#!/usr/bin/env bash
# Generate vertical placeholder dramas as 360p/720p HLS under backend/media/.
# Usage: scripts/gen-media.sh [outdir]   (needs ffmpeg with drawtext)
set -euo pipefail
OUT="${1:-$(dirname "$0")/../media}"
FONT="${FONT:-$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null || echo /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf)}"
EPISODES=6
DUR=10
# slug|title|color
DRAMAS=(
  "mama-in-law-wahala|Mama-in-Law Wahala|0x8B1E3F"
  "lagos-hustle|Lagos Hustle|0x1E5B8B"
  "village-prince|The Village Prince|0x2E7D32"
)
for d in "${DRAMAS[@]}"; do
  IFS='|' read -r slug title color <<<"$d"
  for ep in $(seq 1 $EPISODES); do
    dir="$OUT/$slug/ep$ep"
    [ -f "$dir/master.m3u8" ] && continue
    mkdir -p "$dir/360p" "$dir/720p"
    for r in "360p:360:640:400k" "720p:720:1280:1200k"; do
      IFS=':' read -r name w h br <<<"$r"
      fs=$((w / 12))
      ffmpeg -loglevel error -y -f lavfi -i "color=c=${color}:s=${w}x${h}:r=24:d=${DUR}" \
        -f lavfi -i "sine=frequency=440:duration=${DUR}" \
        -vf "drawtext=fontfile=${FONT}:text='${title}':fontcolor=white:fontsize=${fs}:x=(w-text_w)/2:y=h*0.4,drawtext=fontfile=${FONT}:text='Episode ${ep}':fontcolor=white:fontsize=$((fs*3/2)):x=(w-text_w)/2:y=h*0.55" \
        -c:v libx264 -preset veryfast -b:v "$br" -g 48 -keyint_min 48 -sc_threshold 0 -pix_fmt yuv420p \
        -c:a aac -b:a 64k -shortest \
        -f hls -hls_time 4 -hls_playlist_type vod -hls_segment_filename "$dir/$name/seg_%03d.ts" "$dir/$name/index.m3u8"
    done
    cat > "$dir/master.m3u8" <<M3U
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=360x640
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1300000,RESOLUTION=720x1280
720p/index.m3u8
M3U
  done
  [ -f "$OUT/$slug/cover.jpg" ] || ffmpeg -loglevel error -y -i "$OUT/$slug/ep1/720p/seg_000.ts" -frames:v 1 -q:v 4 "$OUT/$slug/cover.jpg"
done
echo "media generated in $OUT"
