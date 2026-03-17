"""Audio processing helpers for chunk merging and post-processing."""
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


def _as_float32(audio: np.ndarray) -> np.ndarray:
    return np.asarray(audio, dtype=np.float32)


def _silence(sample_rate: int, duration_ms: int, channels: int) -> np.ndarray:
    samples = max(0, int(sample_rate * max(0, duration_ms) / 1000))
    if samples <= 0:
        return np.zeros((0, channels), dtype=np.float32)
    return np.zeros((samples, channels), dtype=np.float32)


def merge_audio_chunks(
    chunks: Iterable[np.ndarray],
    sample_rate: int,
    crossfade_ms: int = 0,
    gap_ms: int = 0,
    leading_silence_ms: int = 0,
) -> np.ndarray:
    """Merge audio chunks with optional crossfade."""
    chunks = list(chunks)
    if not chunks:
        return np.array([], dtype=np.float32)

    output = _as_float32(chunks[0])
    output_2d, output_was_1d = _to_2d(output)
    channels = output_2d.shape[1]
    if leading_silence_ms > 0:
        output_2d = np.concatenate(
            [_silence(sample_rate, leading_silence_ms, channels), output_2d],
            axis=0,
        )

    crossfade_samples = max(0, int(sample_rate * crossfade_ms / 1000))
    gap_samples = _silence(sample_rate, gap_ms, channels)

    for chunk in chunks[1:]:
        chunk = _as_float32(chunk)
        chunk_2d, chunk_was_1d = _to_2d(chunk)

        if output_2d.shape[1] != chunk_2d.shape[1]:
            # Fallback: convert to mono by taking first channel
            output_2d = output_2d[:, :1]
            chunk_2d = chunk_2d[:, :1]
            output_was_1d = True
            channels = 1
            gap_samples = _silence(sample_rate, gap_ms, channels)

        overlap = min(crossfade_samples, len(output_2d), len(chunk_2d))
        if overlap > 0:
            fade_out = np.linspace(1.0, 0.0, overlap, endpoint=False)[:, None]
            fade_in = np.linspace(0.0, 1.0, overlap, endpoint=False)[:, None]
            blended = output_2d[-overlap:] * fade_out + chunk_2d[:overlap] * fade_in
            merged = np.concatenate([output_2d[:-overlap], blended, chunk_2d[overlap:]], axis=0)
        else:
            merged = np.concatenate([output_2d, chunk_2d], axis=0)

        if len(gap_samples) > 0:
            output_2d = np.concatenate([merged, gap_samples], axis=0)
        else:
            output_2d = merged

        output_was_1d = output_was_1d and chunk_was_1d

    return _from_2d(output_2d, output_was_1d)


def normalize_audio_dbfs(audio: np.ndarray, target_dbfs: float = -18.0) -> np.ndarray:
    """Normalize audio to an RMS-like dBFS target while avoiding clipping."""
    samples = _as_float32(audio)
    if samples.size == 0:
        return samples

    rms = float(np.sqrt(np.mean(np.square(samples))))
    if rms <= 1e-8:
        return samples

    target_rms = 10 ** (float(target_dbfs) / 20.0)
    gain = target_rms / rms
    normalized = samples * gain
    peak = float(np.max(np.abs(normalized)))
    if peak > 0.98:
        normalized *= 0.98 / peak
    return normalized.astype(np.float32, copy=False)


def _apply_biquad(audio: np.ndarray, b: np.ndarray, a: np.ndarray) -> np.ndarray:
    audio_2d, was_1d = _to_2d(_as_float32(audio))
    channels = [
        signal.lfilter(b, a, audio_2d[:, channel]).astype(np.float32, copy=False)
        for channel in range(audio_2d.shape[1])
    ]
    return _from_2d(np.stack(channels, axis=1), was_1d)


def apply_tone_profile(audio: np.ndarray, sample_rate: int, profile: str = "none") -> np.ndarray:
    """Apply a light EQ-style tone profile."""
    profile_name = (profile or "none").strip().lower()
    samples = _as_float32(audio)
    if samples.size == 0 or profile_name in {"", "none", "off"}:
        return samples

    low_b, low_a = signal.butter(2, min(0.95, 220.0 / max(1.0, sample_rate / 2.0)), btype="low")
    high_b, high_a = signal.butter(
        2,
        min(0.95, 3200.0 / max(1.0, sample_rate / 2.0)),
        btype="high",
    )
    band_b, band_a = signal.butter(
        2,
        [min(0.94, 350.0 / max(1.0, sample_rate / 2.0)), min(0.99, 2400.0 / max(1.0, sample_rate / 2.0))],
        btype="band",
    )

    low = _apply_biquad(samples, low_b, low_a)
    high = _apply_biquad(samples, high_b, high_a)
    band = _apply_biquad(samples, band_b, band_a)

    if profile_name == "warm":
        processed = samples + (0.18 * low) - (0.08 * high)
    elif profile_name == "bright":
        processed = samples - (0.08 * low) + (0.18 * high)
    elif profile_name == "neutral":
        processed = samples + (0.08 * band)
    else:
        return samples

    peak = float(np.max(np.abs(processed))) if processed.size else 0.0
    if peak > 0.98:
        processed *= 0.98 / peak
    return processed.astype(np.float32, copy=False)


def time_stretch_audio(audio: np.ndarray, rate: float) -> np.ndarray:
    """Time-stretch audio while preserving pitch when librosa is available."""
    samples = _as_float32(audio)
    if samples.size == 0 or abs(rate - 1.0) < 1e-4:
        return samples

    try:
        import librosa

        audio_2d, was_1d = _to_2d(samples)
        stretched = []
        for channel in range(audio_2d.shape[1]):
            stretched.append(
                librosa.effects.time_stretch(audio_2d[:, channel], rate=rate).astype(np.float32)
            )
        min_len = min(len(channel) for channel in stretched)
        merged = np.stack([channel[:min_len] for channel in stretched], axis=1)
        return _from_2d(merged, was_1d)
    except Exception:
        target_len = max(1, int(round(len(samples) / rate)))
        if samples.ndim == 1:
            return signal.resample(samples, target_len).astype(np.float32)
        channels = [
            signal.resample(samples[:, idx], target_len).astype(np.float32)
            for idx in range(samples.shape[1])
        ]
        return np.stack(channels, axis=1)


def pitch_shift_audio(audio: np.ndarray, sample_rate: int, semitones: float) -> np.ndarray:
    """Pitch-shift audio while preserving duration when librosa is available."""
    samples = _as_float32(audio)
    if samples.size == 0 or abs(semitones) < 1e-4:
        return samples

    try:
        import librosa

        audio_2d, was_1d = _to_2d(samples)
        shifted = []
        for channel in range(audio_2d.shape[1]):
            shifted.append(
                librosa.effects.pitch_shift(
                    audio_2d[:, channel],
                    sr=sample_rate,
                    n_steps=semitones,
                ).astype(np.float32)
            )
        min_len = min(len(channel) for channel in shifted)
        merged = np.stack([channel[:min_len] for channel in shifted], axis=1)
        return _from_2d(merged, was_1d)
    except Exception:
        return samples


def blend_audio(processed: np.ndarray, original: np.ndarray, original_mix: float) -> np.ndarray:
    """Blend processed audio with the original signal."""
    mix = float(max(0.0, min(0.95, original_mix)))
    processed_audio = _as_float32(processed)
    original_audio = _as_float32(original)
    if processed_audio.size == 0 or original_audio.size == 0 or mix <= 1e-6:
        return processed_audio

    processed_2d, processed_was_1d = _to_2d(processed_audio)
    original_2d, _ = _to_2d(original_audio)

    if original_2d.shape[1] != processed_2d.shape[1]:
        original_2d = original_2d[:, :1]
        processed_2d = processed_2d[:, :1]
        processed_was_1d = True

    target_len = processed_2d.shape[0]
    if original_2d.shape[0] != target_len:
        channels = [
            signal.resample(original_2d[:, idx], target_len).astype(np.float32)
            for idx in range(original_2d.shape[1])
        ]
        original_2d = np.stack(channels, axis=1)

    blended = (processed_2d * (1.0 - mix)) + (original_2d * mix)
    peak = float(np.max(np.abs(blended))) if blended.size else 0.0
    if peak > 0.98:
        blended *= 0.98 / peak
    return _from_2d(blended.astype(np.float32, copy=False), processed_was_1d)
