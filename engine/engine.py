"""mal2geul speech engine: Qwen3-ASR 1.7B (MLX, 8-bit), loaded once and kept warm. Korean only.

The app runs this script as a child process and talks to it over pipes.

  stdin   A JSON header line, then `bytes` bytes of 16 kHz mono float32 PCM (little-endian).
            {"id": 7, "op": "transcribe", "bytes": 640000, "context": "Qwen, MLX"}
  stdout  One JSON object per line.
            {"event": "loading"} | {"event": "downloading"} | {"event": "ready", "load_ms": 2140}
            {"event": "failed", "error": "..."}
            {"id": 7, "text": "...", "ms": 412, "audio_ms": 15000} | {"id": 7, "error": "..."}
  stderr  Log.

`context` (names, the text before the caret) biases how names and terms are spelled.
The process exits when stdin closes, so it never outlives the app.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import traceback

MODEL = "moona3k/mlx-qwen3-asr-1.7b-8bit"
LANGUAGE = "Korean"
SAMPLE_RATE = 16_000
MODEL_FILES = ["*.json", "*.safetensors", "*.txt", "*.model"]

# Replies get their own copy of stdout; anything a library prints goes to stderr instead.
_replies = os.fdopen(os.dup(1), "w", encoding="utf-8", buffering=1)
os.dup2(2, 1)
sys.stdout = sys.stderr


def reply(payload: dict) -> None:
    _replies.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    _replies.flush()


def model_path() -> str:
    """The cached model, downloaded on first use (about 2 GB)."""
    from huggingface_hub import snapshot_download

    try:
        return snapshot_download(MODEL, allow_patterns=MODEL_FILES, local_files_only=True)
    except Exception:
        reply({"event": "downloading"})
        return snapshot_download(MODEL, allow_patterns=MODEL_FILES)


def load():
    import numpy as np
    from mlx_qwen3_asr import Session

    session = Session(model=model_path())
    # Compile the kernels now so the first real dictation is as fast as the rest.
    noise = (np.random.default_rng(0).standard_normal(SAMPLE_RATE) * 0.01).astype(np.float32)
    session.transcribe(noise, language=LANGUAGE)
    return session


def transcribe(session, audio_bytes: bytes, context: str) -> dict:
    import numpy as np

    audio = np.frombuffer(audio_bytes, dtype="<f4").astype(np.float32)
    audio_ms = int(audio.size * 1000 / SAMPLE_RATE)
    if audio.size < SAMPLE_RATE // 5:
        return {"text": "", "ms": 0, "audio_ms": audio_ms}
    # The context comes from the user's document; keep it from posing as chat-template tokens.
    context = re.sub(r"<\|[^|<>]{0,40}\|>", " ", context)[:2000]
    started = time.perf_counter()
    result = session.transcribe(audio, language=LANGUAGE, context=context)
    return {
        "text": (result.text or "").strip(),
        "ms": int((time.perf_counter() - started) * 1000),
        "audio_ms": audio_ms,
    }


def main() -> None:
    reply({"event": "loading"})
    started = time.perf_counter()
    try:
        import mlx.core as mx

        session = load()
    except Exception as error:  # noqa: BLE001 - report any load failure to the app
        traceback.print_exc()
        reply({"event": "failed", "error": str(error)})
        return
    reply({"event": "ready", "load_ms": int((time.perf_counter() - started) * 1000)})

    stdin = sys.stdin.buffer
    while header_line := stdin.readline():
        if not header_line.strip():
            continue
        try:
            header = json.loads(header_line)
        except json.JSONDecodeError:
            continue
        size = int(header.get("bytes", 0))
        audio = stdin.read(size) if size > 0 else b""
        if len(audio) != size:
            break  # the app went away mid-request

        request_id = header.get("id")
        if header.get("op") != "transcribe":
            reply({"id": request_id, "error": "unknown op"})
            continue
        try:
            reply({"id": request_id, **transcribe(session, audio, str(header.get("context") or ""))})
        except Exception as error:  # noqa: BLE001 - one bad request must not stop the engine
            traceback.print_exc()
            reply({"id": request_id, "error": str(error)})
        finally:
            mx.clear_cache()


if __name__ == "__main__":
    main()
