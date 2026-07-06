#!/usr/bin/env python3
"""Trascrive audio/video in testo. uso: transcribe-av.py <input> <output.txt>
Video/file SENZA audio → output vuoto, exit 0 (skip pulito, verificato 09).
Exit != 0 solo per errori veri (→ quarantena). Modello: $DELERA_WHISPER_MODEL (default small)."""
import os
import sys

def has_audio(path):
    import av  # PyAV (dipendenza di faster-whisper, ffmpeg incluso)
    try:
        with av.open(path) as c:
            return any(s.type == "audio" for s in c.streams)
    except Exception:
        return False

def main():
    src, dst = sys.argv[1], sys.argv[2]
    if not has_audio(src):
        open(dst, "w").close()  # skip pulito
        return 0
    from faster_whisper import WhisperModel
    model = WhisperModel(os.environ.get("DELERA_WHISPER_MODEL", "small"),
                         device="cpu", compute_type="int8")
    segments, _info = model.transcribe(src, vad_filter=True)
    with open(dst, "w") as out:
        for seg in segments:
            out.write(seg.text.strip() + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
