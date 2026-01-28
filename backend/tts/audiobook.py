"""
Audiobook generation module for converting documents to audio using Kokoro TTS.

Handles text chunking, sequential audio generation, and concatenation.
"""

import re
import uuid
import time
import threading
from pathlib import Path
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional
import numpy as np
import soundfile as sf

from .kokoro_engine import get_kokoro_engine, DEFAULT_VOICE


class JobStatus(str, Enum):
    STARTED = "started"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class AudiobookJob:
    """Tracks the state of an audiobook generation job."""
    job_id: str
    title: str
    voice: str
    speed: float
    total_chunks: int
    current_chunk: int = 0
    status: JobStatus = JobStatus.STARTED
    error_message: Optional[str] = None
    audio_path: Optional[Path] = None
    duration_seconds: float = 0.0
    file_size_mb: float = 0.0
    started_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
    _cancel_requested: bool = False

    def request_cancel(self):
        self._cancel_requested = True

    @property
    def is_cancelled(self) -> bool:
        return self._cancel_requested

    @property
    def elapsed_seconds(self) -> float:
        end_time = self.completed_at or time.time()
        return end_time - self.started_at

    @property
    def percent(self) -> float:
        if self.total_chunks == 0:
            return 0.0
        return round((self.current_chunk / self.total_chunks) * 100, 1)


# Global job storage
_jobs: dict[str, AudiobookJob] = {}
_jobs_lock = threading.Lock()


def split_into_sentences(text: str) -> list[str]:
    """Split text into sentences, preserving sentence boundaries."""
    # Normalize whitespace
    text = re.sub(r'\s+', ' ', text).strip()

    # Split on sentence-ending punctuation followed by space or end
    # Handles: . ! ? and common abbreviations
    sentence_pattern = r'(?<=[.!?])\s+(?=[A-Z])|(?<=[.!?])$'

    # Simple split that respects sentence boundaries
    parts = re.split(sentence_pattern, text)

    sentences = []
    for part in parts:
        part = part.strip()
        if part:
            sentences.append(part)

    # If no sentences found, split by newlines or return whole text
    if not sentences:
        sentences = [s.strip() for s in text.split('\n') if s.strip()]

    if not sentences:
        sentences = [text]

    return sentences


def chunk_text_for_kokoro(text: str, max_chars: int = 1500) -> list[str]:
    """
    Split text into chunks that respect:
    1. Sentence boundaries (never split mid-sentence)
    2. ~1500 chars per chunk (~400-500 tokens, safe margin for Kokoro's 510 limit)

    Args:
        text: The full text to chunk
        max_chars: Maximum characters per chunk (default 1500)

    Returns:
        List of text chunks
    """
    sentences = split_into_sentences(text)
    chunks = []
    current_chunk = []
    current_length = 0

    for sentence in sentences:
        sentence_len = len(sentence)

        # If single sentence exceeds max, we need to split it (rare edge case)
        if sentence_len > max_chars:
            # Flush current chunk first
            if current_chunk:
                chunks.append(' '.join(current_chunk))
                current_chunk = []
                current_length = 0

            # Split long sentence by commas or at max_chars
            words = sentence.split()
            temp_chunk = []
            temp_len = 0
            for word in words:
                if temp_len + len(word) + 1 > max_chars and temp_chunk:
                    chunks.append(' '.join(temp_chunk))
                    temp_chunk = [word]
                    temp_len = len(word)
                else:
                    temp_chunk.append(word)
                    temp_len += len(word) + 1
            if temp_chunk:
                chunks.append(' '.join(temp_chunk))
            continue

        # Check if adding this sentence would exceed limit
        if current_length + sentence_len + 1 > max_chars and current_chunk:
            chunks.append(' '.join(current_chunk))
            current_chunk = [sentence]
            current_length = sentence_len
        else:
            current_chunk.append(sentence)
            current_length += sentence_len + 1  # +1 for space

    # Don't forget the last chunk
    if current_chunk:
        chunks.append(' '.join(current_chunk))

    return chunks


def create_audiobook_job(
    text: str,
    title: str,
    voice: str = DEFAULT_VOICE,
    speed: float = 1.0,
) -> AudiobookJob:
    """
    Create a new audiobook generation job.

    Args:
        text: Full document text
        title: Book/document title
        voice: Kokoro voice code
        speed: Playback speed multiplier

    Returns:
        AudiobookJob instance
    """
    job_id = str(uuid.uuid4())[:8]
    chunks = chunk_text_for_kokoro(text)

    job = AudiobookJob(
        job_id=job_id,
        title=title,
        voice=voice,
        speed=speed,
        total_chunks=len(chunks),
    )

    with _jobs_lock:
        _jobs[job_id] = job

    # Start generation in background thread
    thread = threading.Thread(
        target=_generate_audiobook,
        args=(job, chunks),
        daemon=True,
    )
    thread.start()

    return job


def _generate_audiobook(job: AudiobookJob, chunks: list[str]):
    """Background worker that generates the audiobook."""
    engine = get_kokoro_engine()
    outputs_dir = Path(__file__).parent.parent / "outputs"
    outputs_dir.mkdir(exist_ok=True)

    all_audio = []
    sample_rate = 24000  # Kokoro outputs at 24kHz

    try:
        job.status = JobStatus.PROCESSING

        for i, chunk in enumerate(chunks):
            # Check for cancellation
            if job.is_cancelled:
                job.status = JobStatus.CANCELLED
                job.completed_at = time.time()
                return

            job.current_chunk = i + 1

            # Generate audio for this chunk
            engine.load_model()
            generator = engine.pipeline(chunk, voice=job.voice, speed=job.speed)

            chunk_audio = []
            for gs, ps, audio in generator:
                chunk_audio.append(audio)

            if chunk_audio:
                all_audio.append(np.concatenate(chunk_audio))

        # Check cancellation before final write
        if job.is_cancelled:
            job.status = JobStatus.CANCELLED
            job.completed_at = time.time()
            return

        # Concatenate all audio
        if all_audio:
            full_audio = np.concatenate(all_audio)

            # Save to file
            output_file = outputs_dir / f"audiobook-{job.job_id}.wav"
            sf.write(str(output_file), full_audio, sample_rate)

            # Update job with results
            job.audio_path = output_file
            job.duration_seconds = len(full_audio) / sample_rate
            job.file_size_mb = output_file.stat().st_size / (1024 * 1024)
            job.status = JobStatus.COMPLETED
        else:
            job.status = JobStatus.FAILED
            job.error_message = "No audio generated"

    except Exception as e:
        job.status = JobStatus.FAILED
        job.error_message = str(e)

    finally:
        job.completed_at = time.time()


def get_job(job_id: str) -> Optional[AudiobookJob]:
    """Get a job by ID."""
    with _jobs_lock:
        return _jobs.get(job_id)


def cancel_job(job_id: str) -> bool:
    """Request cancellation of a job."""
    job = get_job(job_id)
    if job and job.status in (JobStatus.STARTED, JobStatus.PROCESSING):
        job.request_cancel()
        return True
    return False


def cleanup_old_jobs(max_age_seconds: int = 3600):
    """Remove completed jobs older than max_age_seconds."""
    now = time.time()
    with _jobs_lock:
        to_remove = [
            job_id for job_id, job in _jobs.items()
            if job.completed_at and (now - job.completed_at) > max_age_seconds
        ]
        for job_id in to_remove:
            del _jobs[job_id]
