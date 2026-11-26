"""Writes the bench's real inputs for bench/docinfer-inputs.sh, which validates its arguments and
plans the rows first. Reads the plan's JSON lines on stdin, each a source in the docproc run, the
file to write, and the row's cycle through its sources, and writes each page within docinfer's
area bound at the cycle's gain, and each window at the cycle's offset. It stops on a row GuideLLM
would send as an earlier row's page or window. See bench/README.md.
"""

import hashlib
import json
import math
import sys
import wave

import numpy as np
from guidellm.utils.audio import encode_audio
from guidellm.utils.vision import encode_image
from PIL import Image

MAX_PIXELS = 1120 * 9 * 16 * 16
PAGE_GAIN_STEP = 1 / 128
RATE = 16000


def fit_size(width, height, max_pixels):
    long, short = (height, width) if height > width else (width, height)

    def side(length):
        return max(1, length * short // long)

    length = max(1, min(int(long * math.sqrt(max_pixels / (width * height))), long))
    if side(length) == 1:
        length = min(long, max_pixels)
    else:
        while length > 1 and length * side(length) > max_pixels:
            length -= 1
        while length < long and (length + 1) * side(length + 1) <= max_pixels:
            length += 1
    return (side(length), length) if height > width else (length, side(length))


def page(row):
    with Image.open(row["path"]) as source:
        image = source if source.mode in ("L", "RGB") else source.convert("RGB")
        width, height = image.size
        if width * height > MAX_PIXELS:
            image = image.resize(fit_size(width, height, MAX_PIXELS), Image.Resampling.BOX)
        if row["cycle"]:
            pixels = np.asarray(image, dtype=np.float64) * (1 - row["cycle"] * PAGE_GAIN_STEP)
            image = Image.fromarray(np.clip(np.rint(pixels), 0, 255).astype(np.uint8))
        image.save(row["dest"], format="PNG")
    return encode_image(row["dest"])["image"].encode()


def window(row):
    with wave.open(row["path"], "rb") as source:
        shape = (source.getnchannels(), source.getsampwidth(), source.getframerate())
        if shape != (1, 2, RATE):
            raise RuntimeError(f"{row['path']} is {shape} channels, bytes and Hz, not (1, 2, {RATE})")
        pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    pcm = np.clip(pcm.astype(np.int32) + row["cycle"], -32768, 32767).astype("<i2")
    with wave.open(row["dest"], "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    return encode_audio(row["dest"], audio_format="wav", encode_sample_rate=RATE)["audio"]


def main():
    writers = {"page": page, "window": window}
    seen = set()
    counts = {kind: 0 for kind in writers}
    for line in sys.stdin:
        row = json.loads(line)
        digest = (row["kind"], hashlib.sha256(writers[row["kind"]](row)).digest())
        if digest in seen:
            raise RuntimeError(f"{row['dest']} repeats an earlier row's {row['kind']}, from {row['source']}")
        seen.add(digest)
        counts[row["kind"]] += 1
    print(f"wrote {counts['page']} pages and {counts['window']} windows")


if __name__ == "__main__":
    main()
