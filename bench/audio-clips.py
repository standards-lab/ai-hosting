"""Writes the audio bench's speech from the LibriSpeech dummy set for bench/audio-clips.sh, which
validates the arguments first: the audio capacity scenarios' clips, 30 s windows, JSONL rows and
each row's own WAV, or the probe's clips of about 10, 30, 60 and 120 s. See bench/README.md.
"""

import argparse
import hashlib
import json
import subprocess
import wave
from pathlib import Path

import datasets
import numpy as np

DATASET = "hf-internal-testing/librispeech_asr_dummy"
RATE = 16000
PROMPT = (
    "Transcribe the following speech segment in English into English text. "
    "Only output the transcription, with no newlines."
)
SHORT_ROWS = 5400
WINDOW = (28, 30)
WINDOW_ROWS = 1800
PROBE_SECONDS = (10, 30, 60, 120)
GAIN_STEP = 1 / 4096
WINDOWS_JQ = Path(__file__).with_name("audio-windows.jq")


def load_clips():
    rows = datasets.load_dataset(DATASET, "clean", split="validation")
    clips = []
    for row in rows:
        samples = row["audio"].get_all_samples()
        if samples.sample_rate != RATE:
            raise RuntimeError(f"{row['id']} is {samples.sample_rate} Hz, not {RATE}")
        pcm = np.clip(samples.data.mean(dim=0).numpy() * 32768, -32768, 32767).astype("<i2")
        clips.append({"id": row["id"], "text": row["text"], "pcm": pcm})
    return clips


def windows(clips, lo, hi):
    result = subprocess.run(
        ["jq", "-c", "--argjson", "rate", str(RATE), "--argjson", "lo", str(lo),
         "--argjson", "hi", str(hi), "-f", str(WINDOWS_JQ)],
        input=json.dumps([len(clip["pcm"]) for clip in clips]),
        capture_output=True, text=True, check=True,
    )
    return [[clips[i] for i in window] for window in json.loads(result.stdout)]


def write_wav(path, pcm):
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def write(path, window):
    pcm = np.concatenate([clip["pcm"] for clip in window])
    write_wav(path, pcm)
    path.with_suffix(".txt").write_text(" ".join(clip["text"] for clip in window) + "\n")
    seconds = len(pcm) / RATE
    print(f"{path} {seconds:.2f} s, {len(window)} clips from {window[0]['id']} to {window[-1]['id']}")
    return {"path": path.resolve(), "pcm": pcm}


def write_rows(path, sources, count, seen, first_cycle):
    directory = path.parent / f"rows-{path.stem}"
    directory.mkdir(parents=True, exist_ok=True)
    with path.open("w") as out:
        for i in range(count):
            source = sources[i % len(sources)]
            gain = 1 + (first_cycle + i // len(sources)) * GAIN_STEP
            pcm = np.clip(np.rint(source["pcm"] * gain), -32768, 32767).astype("<i2")
            digest = hashlib.sha256(pcm.tobytes()).digest()
            if digest in seen:
                raise RuntimeError(f"row {i} repeats an earlier row's audio, from {source['path']}")
            seen.add(digest)
            wav = directory / f"{i:05d}.wav"
            write_wav(wav, pcm)
            out.write(json.dumps({"prompt": PROMPT, "audio": str(wav.resolve())}) + "\n")
    print(f"{path} {count} rows over {len(sources)} files, each row its own WAV under {directory}")
    return first_cycle + -(-count // len(sources))


def scenarios(clips, output):
    (output / "clips").mkdir(parents=True, exist_ok=True)
    (output / "windows-30").mkdir(parents=True, exist_ok=True)
    short = [write(output / "clips" / f"{clip['id']}.wav", [clip]) for clip in clips]
    long = [write(output / "windows-30" / f"{i:02d}.wav", window)
            for i, window in enumerate(windows(clips, *WINDOW))]
    if not long:
        raise RuntimeError(f"no window of {WINDOW[0]} to {WINDOW[1]} s in {DATASET}")
    seen = set()
    cycle = write_rows(output / "short.jsonl", short, SHORT_ROWS, seen, 0)
    write_rows(output / "windows-30.jsonl", long, WINDOW_ROWS, seen, cycle)


def probe(clips, output):
    output.mkdir(parents=True, exist_ok=True)
    for seconds in PROBE_SECONDS:
        found = windows(clips, seconds * 14 / 15, seconds)
        if not found:
            raise RuntimeError(f"no window of about {seconds} s in {DATASET}")
        write(output / f"{seconds}s.wav", found[0])


def main():
    parser = argparse.ArgumentParser(prog="bench/audio-clips.py")
    parser.add_argument("what", choices=["scenarios", "probe"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    clips = load_clips()
    if args.what == "scenarios":
        scenarios(clips, args.output)
    else:
        probe(clips, args.output)


if __name__ == "__main__":
    main()
