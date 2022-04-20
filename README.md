# IP TV Playlist

# FAQ

## How to convert image to single frame video

```
ffmpeg -f image2 -loop 1 -i input.jpg -t 30 -c:v libx264 -crf 1 -vf "format=yuv420p" -profile:v high output.mp4
```
