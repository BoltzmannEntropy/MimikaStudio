"""
Audiobook generation module for converting documents to audio using Kokoro TTS.

Enhanced with features from audiblez and pdf-narrator:
- spaCy-based sentence tokenization for robust chunking
- Character-based progress tracking with chars/sec and ETA
- PDF chapter/TOC extraction
- Smart header/footer detection
- M4B audiobook format with chapter markers

Performance target: ~60 chars/sec on M2 MacBook Pro CPU (matching audiblez)
"""

import re
import uuid
import time
import threading
import subprocess
import shutil
from pathlib import Path
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Literal, List, Tuple
from types import SimpleNamespace
import numpy as np
import soundfile as sf

from .kokoro_engine import get_kokoro_engine, DEFAULT_VOICE

# Output format type
OutputFormat = Literal["wav", "mp3", "m4b"]

# Subtitle format type
SubtitleFormat = Literal["none", "srt", "vtt"]

# Try to load spaCy for robust sentence tokenization
_nlp = None
_spacy_available = False

def _get_spacy_nlp():
    """Lazy-load spaCy with sentencizer for sentence splitting."""
    global _nlp, _spacy_available
    if _nlp is not None:
        return _nlp

    try:
        import spacy
        # Use blank English model with just sentencizer (lightweight)
        _nlp = spacy.blank("en")
        _nlp.add_pipe("sentencizer")
        _spacy_available = True
        print("[Audiobook] spaCy sentencizer loaded successfully")
    except ImportError:
        print("[Audiobook] spaCy not available, using regex fallback")
        _spacy_available = False
        _nlp = None
    except Exception as e:
        print(f"[Audiobook] spaCy load error: {e}, using regex fallback")
        _spacy_available = False
        _nlp = None

    return _nlp


class JobStatus(str, Enum):
    STARTED = "started"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class SubtitleEntry:
    """A single subtitle entry with timing information."""
    index: int
    start_time: float  # seconds
    end_time: float    # seconds
    text: str

    def to_srt(self) -> str:
        """Convert to SRT format string."""
        def format_time(seconds: float) -> str:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            secs = int(seconds % 60)
            millis = int((seconds % 1) * 1000)
            return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"

        return f"{self.index}\n{format_time(self.start_time)} --> {format_time(self.end_time)}\n{self.text}\n"

    def to_vtt(self) -> str:
        """Convert to WebVTT format string."""
        def format_time(seconds: float) -> str:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            secs = int(seconds % 60)
            millis = int((seconds % 1) * 1000)
            return f"{hours:02d}:{minutes:02d}:{secs:02d}.{millis:03d}"

        return f"{format_time(self.start_time)} --> {format_time(self.end_time)}\n{self.text}\n"


@dataclass
class Chapter:
    """Represents a chapter or section in a document."""
    title: str
    text: str
    page_start: int = 0
    page_end: int = 0
    level: int = 1  # Heading level (1 = top level)


@dataclass
class AudiobookJob:
    """Tracks the state of an audiobook generation job."""
    job_id: str
    title: str
    voice: str
    speed: float
    total_chunks: int
    output_format: OutputFormat = "wav"
    subtitle_format: SubtitleFormat = "none"
    current_chunk: int = 0
    status: JobStatus = JobStatus.STARTED
    error_message: Optional[str] = None
    audio_path: Optional[Path] = None
    subtitle_path: Optional[Path] = None
    duration_seconds: float = 0.0
    file_size_mb: float = 0.0
    started_at: float = field(default_factory=time.time)
    completed_at: Optional[float] = None
    _cancel_requested: bool = False

    # Enhanced progress tracking (like audiblez)
    total_chars: int = 0
    processed_chars: int = 0
    chars_per_sec: float = 0.0
    eta_seconds: float = 0.0

    # Chapter information
    chapters: List[Chapter] = field(default_factory=list)
    current_chapter: int = 0

    # Subtitle entries (built during generation)
    subtitles: List[SubtitleEntry] = field(default_factory=list)

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
        # Use character-based progress for more accuracy
        if self.total_chars > 0:
            return round((self.processed_chars / self.total_chars) * 100, 1)
        if self.total_chunks == 0:
            return 0.0
        return round((self.current_chunk / self.total_chunks) * 100, 1)

    def update_progress(self, chars_processed: int):
        """Update progress with character count (like audiblez stats)."""
        self.processed_chars += chars_processed
        elapsed = self.elapsed_seconds
        if elapsed > 0:
            self.chars_per_sec = self.processed_chars / elapsed
            remaining_chars = self.total_chars - self.processed_chars
            if self.chars_per_sec > 0:
                self.eta_seconds = remaining_chars / self.chars_per_sec


# Global job storage
_jobs: dict[str, AudiobookJob] = {}
_jobs_lock = threading.Lock()


def split_into_sentences_spacy(text: str) -> list[str]:
    """Split text into sentences using spaCy (like audiblez)."""
    nlp = _get_spacy_nlp()
    if nlp is None:
        return split_into_sentences_regex(text)

    # Normalize whitespace
    text = re.sub(r'\s+', ' ', text).strip()

    doc = nlp(text)
    sentences = [sent.text.strip() for sent in doc.sents if sent.text.strip()]

    return sentences if sentences else [text]


def split_into_sentences_regex(text: str) -> list[str]:
    """Fallback regex-based sentence splitting."""
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


def split_into_sentences(text: str) -> list[str]:
    """Split text into sentences using best available method."""
    if _spacy_available or _get_spacy_nlp() is not None:
        return split_into_sentences_spacy(text)
    return split_into_sentences_regex(text)


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


# ============== PDF Processing (like pdf-narrator) ==============

def extract_pdf_with_toc(pdf_path: str) -> Tuple[str, List[Chapter]]:
    """
    Extract text from PDF with table of contents support.
    Skips headers, footers, and page numbers (like pdf-narrator).

    Returns:
        Tuple of (full_text, chapters)
    """
    chapters = []
    full_text_parts = []

    try:
        import fitz  # pymupdf

        doc = fitz.open(pdf_path)
        toc = doc.get_toc()  # [(level, title, page), ...]

        # If we have a TOC, use it to create chapters
        if toc:
            for i, (level, title, page) in enumerate(toc):
                # Determine page range for this chapter
                page_start = page - 1  # 0-indexed
                page_end = toc[i + 1][2] - 1 if i + 1 < len(toc) else len(doc)

                chapter_text_parts = []
                for page_num in range(page_start, page_end):
                    if page_num < len(doc):
                        page_obj = doc[page_num]
                        text = _extract_page_text_clean(page_obj)
                        if text:
                            chapter_text_parts.append(text)

                chapter_text = '\n\n'.join(chapter_text_parts)
                if chapter_text.strip():
                    chapters.append(Chapter(
                        title=title,
                        text=chapter_text,
                        page_start=page_start,
                        page_end=page_end,
                        level=level
                    ))
                    full_text_parts.append(f"## {title}\n\n{chapter_text}")
        else:
            # No TOC - extract all pages as single chapter
            for page in doc:
                text = _extract_page_text_clean(page)
                if text:
                    full_text_parts.append(text)

            full_text = '\n\n'.join(full_text_parts)
            if full_text.strip():
                chapters.append(Chapter(
                    title="Full Document",
                    text=full_text,
                    page_start=0,
                    page_end=len(doc)
                ))

        doc.close()

    except ImportError:
        # Fallback to PyPDF2
        return _extract_pdf_pypdf2(pdf_path)
    except Exception as e:
        print(f"[Audiobook] pymupdf error: {e}, trying PyPDF2")
        return _extract_pdf_pypdf2(pdf_path)

    full_text = '\n\n'.join(full_text_parts)
    return full_text, chapters


def _extract_page_text_clean(page) -> str:
    """
    Extract text from a page, removing headers/footers/page numbers.
    Based on pdf-narrator's approach.
    """
    # Get page dimensions
    rect = page.rect
    page_height = rect.height
    page_width = rect.width

    # Skip top 5% (headers) and bottom 8% (footers/page numbers)
    header_margin = page_height * 0.05
    footer_margin = page_height * 0.08

    # Create clip rectangle excluding margins
    clip_rect = (0, header_margin, page_width, page_height - footer_margin)

    # Extract text from clipped area
    text = page.get_text("text", clip=clip_rect)

    # Clean up the text
    if text:
        # Remove excessive whitespace
        text = re.sub(r'\n{3,}', '\n\n', text)
        # Remove page number patterns
        text = re.sub(r'^\s*\d+\s*$', '', text, flags=re.MULTILINE)
        text = text.strip()

    return text


def _extract_pdf_pypdf2(pdf_path: str) -> Tuple[str, List[Chapter]]:
    """Fallback PDF extraction using PyPDF2."""
    try:
        from PyPDF2 import PdfReader

        reader = PdfReader(pdf_path)
        text_parts = []

        for page in reader.pages:
            text = page.extract_text()
            if text:
                # Basic cleanup
                text = re.sub(r'\n{3,}', '\n\n', text)
                text_parts.append(text.strip())

        full_text = '\n\n'.join(text_parts)
        chapters = [Chapter(
            title="Full Document",
            text=full_text,
            page_start=0,
            page_end=len(reader.pages)
        )] if full_text.strip() else []

        return full_text, chapters

    except Exception as e:
        print(f"[Audiobook] PyPDF2 error: {e}")
        return "", []


# ============== EPUB Processing (like audiblez) ==============

def extract_epub_chapters(epub_path: str) -> Tuple[str, List[Chapter]]:
    """
    Extract chapters from EPUB file (like audiblez).
    """
    chapters = []
    full_text_parts = []

    try:
        import ebooklib
        from ebooklib import epub
        from bs4 import BeautifulSoup

        book = epub.read_epub(epub_path)

        # Get chapters
        chapter_idx = 0
        for item in book.get_items():
            if item.get_type() == ebooklib.ITEM_DOCUMENT:
                # Parse HTML content
                soup = BeautifulSoup(item.get_content(), 'html.parser')

                # Extract title from h1-h4 or use filename
                title_tag = soup.find(['h1', 'h2', 'h3', 'h4', 'title'])
                title = title_tag.get_text().strip() if title_tag else f"Chapter {chapter_idx + 1}"

                # Extract text from content tags (like audiblez)
                text_parts = []
                for tag in soup.find_all(['p', 'h1', 'h2', 'h3', 'h4', 'li']):
                    text = tag.get_text().strip()
                    if text:
                        # Ensure sentences end with period (like audiblez)
                        if not text.endswith(('.', '!', '?', ':', ';')):
                            text += '.'
                        text_parts.append(text)

                chapter_text = '\n'.join(text_parts)

                # Filter by minimum length (like audiblez find_good_chapters)
                if len(chapter_text) > 100:
                    chapters.append(Chapter(
                        title=title,
                        text=chapter_text,
                        level=1
                    ))
                    full_text_parts.append(f"## {title}\n\n{chapter_text}")
                    chapter_idx += 1

    except ImportError:
        print("[Audiobook] ebooklib not available for EPUB")
        return "", []
    except Exception as e:
        print(f"[Audiobook] EPUB error: {e}")
        return "", []

    full_text = '\n\n'.join(full_text_parts)
    return full_text, chapters


# ============== Job Management ==============

def create_audiobook_job(
    text: str,
    title: str,
    voice: str = DEFAULT_VOICE,
    speed: float = 1.0,
    output_format: OutputFormat = "wav",
    subtitle_format: SubtitleFormat = "none",
    chapters: Optional[List[Chapter]] = None,
) -> AudiobookJob:
    """
    Create a new audiobook generation job.

    Args:
        text: Full document text
        title: Book/document title
        voice: Kokoro voice code
        speed: Playback speed multiplier
        output_format: Output format ("wav", "mp3", or "m4b")
        subtitle_format: Subtitle format ("none", "srt", or "vtt")
        chapters: Optional list of chapters for M4B format

    Returns:
        AudiobookJob instance
    """
    job_id = str(uuid.uuid4())[:8]
    chunks = chunk_text_for_kokoro(text)
    total_chars = sum(len(c) for c in chunks)

    job = AudiobookJob(
        job_id=job_id,
        title=title,
        voice=voice,
        speed=speed,
        total_chunks=len(chunks),
        total_chars=total_chars,
        output_format=output_format,
        subtitle_format=subtitle_format,
        chapters=chapters or [],
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


def create_audiobook_from_file(
    file_path: str,
    title: Optional[str] = None,
    voice: str = DEFAULT_VOICE,
    speed: float = 1.0,
    output_format: OutputFormat = "wav",
    subtitle_format: SubtitleFormat = "none",
) -> AudiobookJob:
    """
    Create audiobook from a file (PDF, EPUB, TXT, etc.).
    Automatically extracts chapters and handles format-specific processing.

    Args:
        file_path: Path to the document
        title: Optional title (defaults to filename)
        voice: Kokoro voice code
        speed: Playback speed multiplier
        output_format: Output format ("wav", "mp3", or "m4b")
        subtitle_format: Subtitle format ("none", "srt", or "vtt")

    Returns:
        AudiobookJob instance
    """
    path = Path(file_path)
    ext = path.suffix.lower()

    if title is None:
        title = path.stem

    text = ""
    chapters = []

    if ext == '.pdf':
        text, chapters = extract_pdf_with_toc(file_path)
    elif ext == '.epub':
        text, chapters = extract_epub_chapters(file_path)
    elif ext in ('.txt', '.md'):
        text = path.read_text(encoding='utf-8')
        chapters = [Chapter(title=title, text=text)]
    elif ext == '.docx':
        try:
            from docx import Document
            doc = Document(file_path)
            text = '\n\n'.join(para.text for para in doc.paragraphs if para.text.strip())
            chapters = [Chapter(title=title, text=text)]
        except ImportError:
            raise ValueError("python-docx not installed for DOCX support")
    else:
        raise ValueError(f"Unsupported file format: {ext}")

    if not text.strip():
        raise ValueError("No text extracted from document")

    return create_audiobook_job(
        text=text,
        title=title,
        voice=voice,
        speed=speed,
        output_format=output_format,
        subtitle_format=subtitle_format,
        chapters=chapters,
    )


def _convert_to_mp3(wav_path: Path, mp3_path: Path, bitrate: str = "192k") -> Path:
    """Convert WAV file to MP3 using pydub."""
    from pydub import AudioSegment

    audio = AudioSegment.from_wav(str(wav_path))
    audio.export(str(mp3_path), format="mp3", bitrate=bitrate)

    # Remove the temporary WAV file
    wav_path.unlink()

    return mp3_path


def _convert_to_m4b(
    wav_path: Path,
    m4b_path: Path,
    title: str,
    chapters: List[Chapter],
    chapter_timestamps: List[Tuple[float, float]],  # (start_sec, end_sec) per chapter
) -> Path:
    """
    Convert WAV to M4B audiobook format with chapter markers using ffmpeg.
    Based on audiblez's approach.
    """
    if not shutil.which('ffmpeg'):
        print("[Audiobook] ffmpeg not found, falling back to MP3")
        mp3_path = m4b_path.with_suffix('.mp3')
        return _convert_to_mp3(wav_path, mp3_path)

    # Create chapter metadata file for ffmpeg
    metadata_path = wav_path.with_suffix('.txt')
    with open(metadata_path, 'w') as f:
        f.write(";FFMETADATA1\n")
        f.write(f"title={title}\n")
        f.write(f"artist=MimikaStudio\n\n")

        for i, (chapter, (start, end)) in enumerate(zip(chapters, chapter_timestamps)):
            f.write("[CHAPTER]\n")
            f.write("TIMEBASE=1/1000\n")
            f.write(f"START={int(start * 1000)}\n")
            f.write(f"END={int(end * 1000)}\n")
            f.write(f"title={chapter.title}\n\n")

    # Convert to M4B using ffmpeg
    try:
        subprocess.run([
            'ffmpeg', '-y',
            '-i', str(wav_path),
            '-i', str(metadata_path),
            '-map_metadata', '1',
            '-c:a', 'aac',
            '-b:a', '128k',
            str(m4b_path)
        ], check=True, capture_output=True)

        # Cleanup
        wav_path.unlink()
        metadata_path.unlink()

        return m4b_path

    except subprocess.CalledProcessError as e:
        print(f"[Audiobook] ffmpeg error: {e.stderr.decode()}")
        # Fallback to MP3
        mp3_path = m4b_path.with_suffix('.mp3')
        metadata_path.unlink(missing_ok=True)
        return _convert_to_mp3(wav_path, mp3_path)


def _write_subtitles(job: AudiobookJob, outputs_dir: Path) -> Optional[Path]:
    """Write subtitle file in requested format."""
    if job.subtitle_format == "none" or not job.subtitles:
        return None

    if job.subtitle_format == "srt":
        subtitle_file = outputs_dir / f"audiobook-{job.job_id}.srt"
        with open(subtitle_file, 'w', encoding='utf-8') as f:
            for entry in job.subtitles:
                f.write(entry.to_srt())
                f.write("\n")
    elif job.subtitle_format == "vtt":
        subtitle_file = outputs_dir / f"audiobook-{job.job_id}.vtt"
        with open(subtitle_file, 'w', encoding='utf-8') as f:
            f.write("WEBVTT\n\n")
            for entry in job.subtitles:
                f.write(entry.to_vtt())
                f.write("\n")
    else:
        return None

    return subtitle_file


def _generate_audiobook(job: AudiobookJob, chunks: list[str]):
    """
    Background worker that generates the audiobook.
    Enhanced with character-based progress tracking (like audiblez).
    Now also generates timestamped subtitles (like abogen).
    """
    engine = get_kokoro_engine()
    outputs_dir = Path(__file__).parent.parent / "outputs"
    outputs_dir.mkdir(parents=True, exist_ok=True)

    all_audio = []
    sample_rate = 24000  # Kokoro outputs at 24kHz
    chapter_timestamps = []  # For M4B chapter markers
    current_time = 0.0
    subtitle_index = 1  # SRT indices start at 1

    try:
        job.status = JobStatus.PROCESSING

        # Track which chapter we're in
        chapter_char_counts = []
        if job.chapters:
            for ch in job.chapters:
                chapter_char_counts.append(len(ch.text))

        chars_processed_total = 0
        current_chapter_idx = 0
        chapter_start_time = 0.0

        for i, chunk in enumerate(chunks):
            # Check for cancellation
            if job.is_cancelled:
                job.status = JobStatus.CANCELLED
                job.completed_at = time.time()
                return

            job.current_chunk = i + 1
            chunk_chars = len(chunk)
            chunk_start_time = current_time

            # Generate audio for this chunk
            engine.load_model()
            generator = engine.pipeline(chunk, voice=job.voice, speed=job.speed)

            chunk_audio = []
            for gs, ps, audio in generator:
                chunk_audio.append(audio)

            if chunk_audio:
                chunk_audio_concat = np.concatenate(chunk_audio)
                all_audio.append(chunk_audio_concat)

                # Update timing for chapter markers
                chunk_duration = len(chunk_audio_concat) / sample_rate
                current_time += chunk_duration

                # Create subtitle entry for this chunk (if subtitles enabled)
                if job.subtitle_format != "none":
                    # Clean up chunk text for subtitle display
                    subtitle_text = chunk.strip()
                    # Limit subtitle length for readability (split long chunks)
                    max_subtitle_len = 200
                    if len(subtitle_text) > max_subtitle_len:
                        # Split into multiple subtitle entries
                        words = subtitle_text.split()
                        current_sub_text = []
                        current_sub_len = 0
                        sub_start = chunk_start_time
                        words_per_sec = len(words) / chunk_duration if chunk_duration > 0 else 10

                        for word in words:
                            current_sub_text.append(word)
                            current_sub_len += len(word) + 1

                            if current_sub_len >= max_subtitle_len:
                                sub_duration = len(current_sub_text) / words_per_sec
                                job.subtitles.append(SubtitleEntry(
                                    index=subtitle_index,
                                    start_time=sub_start,
                                    end_time=sub_start + sub_duration,
                                    text=' '.join(current_sub_text)
                                ))
                                subtitle_index += 1
                                sub_start += sub_duration
                                current_sub_text = []
                                current_sub_len = 0

                        # Add remaining words
                        if current_sub_text:
                            job.subtitles.append(SubtitleEntry(
                                index=subtitle_index,
                                start_time=sub_start,
                                end_time=current_time,
                                text=' '.join(current_sub_text)
                            ))
                            subtitle_index += 1
                    else:
                        job.subtitles.append(SubtitleEntry(
                            index=subtitle_index,
                            start_time=chunk_start_time,
                            end_time=current_time,
                            text=subtitle_text
                        ))
                        subtitle_index += 1

            # Update character-based progress (like audiblez)
            chars_processed_total += chunk_chars
            job.update_progress(chunk_chars)

            # Track chapter boundaries for M4B
            if chapter_char_counts and current_chapter_idx < len(chapter_char_counts):
                if chars_processed_total >= sum(chapter_char_counts[:current_chapter_idx + 1]):
                    chapter_timestamps.append((chapter_start_time, current_time))
                    chapter_start_time = current_time
                    current_chapter_idx += 1
                    job.current_chapter = current_chapter_idx

        # Finalize last chapter timestamp
        if job.chapters and len(chapter_timestamps) < len(job.chapters):
            chapter_timestamps.append((chapter_start_time, current_time))

        # Check cancellation before final write
        if job.is_cancelled:
            job.status = JobStatus.CANCELLED
            job.completed_at = time.time()
            return

        # Concatenate all audio
        if all_audio:
            full_audio = np.concatenate(all_audio)
            job.duration_seconds = len(full_audio) / sample_rate

            # Save to WAV first
            wav_file = outputs_dir / f"audiobook-{job.job_id}.wav"
            sf.write(str(wav_file), full_audio, sample_rate)

            # Convert to requested format
            if job.output_format == "mp3":
                mp3_file = outputs_dir / f"audiobook-{job.job_id}.mp3"
                output_file = _convert_to_mp3(wav_file, mp3_file)
            elif job.output_format == "m4b":
                m4b_file = outputs_dir / f"audiobook-{job.job_id}.m4b"
                output_file = _convert_to_m4b(
                    wav_file, m4b_file, job.title,
                    job.chapters, chapter_timestamps
                )
            else:
                output_file = wav_file

            # Write subtitle file if requested
            subtitle_file = _write_subtitles(job, outputs_dir)
            if subtitle_file:
                job.subtitle_path = subtitle_file
                print(f"[Audiobook] Subtitles written: {subtitle_file.name}")

            # Update job with results
            job.audio_path = output_file
            job.file_size_mb = output_file.stat().st_size / (1024 * 1024)
            job.status = JobStatus.COMPLETED

            # Final stats
            elapsed = job.elapsed_seconds
            if elapsed > 0:
                job.chars_per_sec = job.total_chars / elapsed
                print(f"[Audiobook] Completed: {job.total_chars} chars in {elapsed:.1f}s "
                      f"({job.chars_per_sec:.1f} chars/sec)")
        else:
            job.status = JobStatus.FAILED
            job.error_message = "No audio generated"

    except Exception as e:
        job.status = JobStatus.FAILED
        job.error_message = str(e)
        import traceback
        traceback.print_exc()

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


def format_eta(seconds: float) -> str:
    """Format ETA in human-readable format (like audiblez strfdelta)."""
    if seconds <= 0:
        return "calculating..."

    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)

    if hours > 0:
        return f"{hours}h {minutes}m {secs}s"
    elif minutes > 0:
        return f"{minutes}m {secs}s"
    else:
        return f"{secs}s"
