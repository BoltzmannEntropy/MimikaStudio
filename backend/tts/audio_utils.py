"""Audio processing helpers for chunk merging and resampling."""
from __future__ import annotations

from typing import Iterable
import numpy as np
from scipy import signal


def resample_audio(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    """Resample audio to target sample rate."""
    if orig_sr == target_sr:
        return audio

    if audio.ndim == 1:
        return signal.resample_poly(audio, target_sr, orig_sr)

    channels = []
    for ch in range(audio.shape[1]):
        channels.append(signal.resample_poly(audio[:, ch], target_sr, orig_sr))
    return np.stack(channels, axis=1)


def _to_2d(audio: np.ndarray) -> tuple[np.ndarray, bool]:
    if audio.ndim == 1:
        return audio[:, None], True
    return audio, False


def _from_2d(audio: np.ndarray, was_1d: bool) -> np.ndarray:
    return audio[:, 0] if was_1d else audio


def merge_audio_chunks(
    chunks: Iterable[np.ndarray],
    sample_rate: int,
    crossfade_ms: int = 0,
) -> np.ndarray:
    """Merge audio chunks with optional crossfade."""
    chunks = list(chunks)
    if not chunks:
        return np.array([], dtype=np.float32)

    output = np.asarray(chunks[0], dtype=np.float32)
    output_2d, output_was_1d = _to_2d(output)

    crossfade_samples = max(0, int(sample_rate * crossfade_ms / 1000))

    for chunk in chunks[1:]:
        chunk = np.asarray(chunk, dtype=np.float32)
        chunk_2d, chunk_was_1d = _to_2d(chunk)

        if output_2d.shape[1] != chunk_2d.shape[1]:
            # Fallback: convert to mono by taking first channel
            output_2d = output_2d[:, :1]
            chunk_2d = chunk_2d[:, :1]
            output_was_1d = True

        overlap = min(crossfade_samples, len(output_2d), len(chunk_2d))
        if overlap > 0:
            fade_out = np.linspace(1.0, 0.0, overlap, endpoint=False)[:, None]
            fade_in = np.linspace(0.0, 1.0, overlap, endpoint=False)[:, None]
            blended = output_2d[-overlap:] * fade_out + chunk_2d[:overlap] * fade_in
            output_2d = np.concatenate(
                [output_2d[:-overlap], blended, chunk_2d[overlap:]],
                axis=0,
            )
        else:
            output_2d = np.concatenate([output_2d, chunk_2d], axis=0)

        output_was_1d = output_was_1d and chunk_was_1d

    return _from_2d(output_2d, output_was_1d)
