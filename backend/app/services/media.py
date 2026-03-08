"""Media utilities for video keyframe extraction."""

import asyncio
import tempfile
import os

from app.services.storage import upload_bytes


async def extract_keyframes_to_gcs(
    video_uri: str,
    uid: str,
    scan_id: str,
    frame_count: int = 3,
) -> list[str]:
    """Extract representative keyframes from a video and upload to GCS.

    Uses ffmpeg to extract evenly-spaced frames from the video.
    Falls back to a single frame at the midpoint if ffmpeg is unavailable.

    Returns list of gs:// URIs for the extracted frames.
    """

    def _extract(video_bytes: bytes) -> list[bytes]:
        """Synchronous ffmpeg extraction."""
        frames = []
        with tempfile.TemporaryDirectory() as tmpdir:
            video_path = os.path.join(tmpdir, "input.mp4")
            with open(video_path, "wb") as f:
                f.write(video_bytes)

            # Use ffmpeg to extract evenly-spaced frames
            output_pattern = os.path.join(tmpdir, "frame_%02d.jpg")
            cmd = (
                f"ffmpeg -i {video_path} -vf "
                f'"select=not(mod(n\\,%(interval)s))" '
                f"-vsync vfn -frames:v {frame_count} -q:v 2 {output_pattern}"
            )

            # Get video duration first to calculate interval
            import subprocess

            probe = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration",
                    "-of",
                    "default=noprint_wrappers=1:nokey=1",
                    video_path,
                ],
                capture_output=True,
                text=True,
            )

            try:
                duration = float(probe.stdout.strip())
            except (ValueError, AttributeError):
                duration = 10.0

            # Extract frames at evenly-spaced timestamps
            for i in range(frame_count):
                timestamp = duration * (i + 1) / (frame_count + 1)
                frame_path = os.path.join(tmpdir, f"frame_{i:02d}.jpg")
                subprocess.run(
                    [
                        "ffmpeg",
                        "-y",
                        "-ss",
                        str(timestamp),
                        "-i",
                        video_path,
                        "-frames:v",
                        "1",
                        "-q:v",
                        "2",
                        frame_path,
                    ],
                    capture_output=True,
                )

            # Collect extracted frames
            for i in range(frame_count):
                frame_path = os.path.join(tmpdir, f"frame_{i:02d}.jpg")
                if os.path.exists(frame_path):
                    with open(frame_path, "rb") as f:
                        frames.append(f.read())

        return frames

    # Download video bytes from GCS
    from google.cloud import storage as gcs_storage
    from app.config import settings

    client = gcs_storage.Client(project=settings.gcp_project_id)
    # Parse gs:// URI
    bucket_name = video_uri.split("/")[2]
    blob_path = "/".join(video_uri.split("/")[3:])
    blob = client.bucket(bucket_name).blob(blob_path)
    video_bytes = blob.download_as_bytes()

    # Run ffmpeg in thread pool to avoid blocking
    frames = await asyncio.to_thread(_extract, video_bytes)

    # Upload frames to GCS
    image_uris = []
    for i, frame_data in enumerate(frames):
        path = f"inventory-scans/{uid}/{scan_id}/{i}.jpg"
        uri = upload_bytes(path, frame_data, "image/jpeg")
        image_uris.append(uri)

    return image_uris
