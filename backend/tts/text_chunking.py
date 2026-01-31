"""Text chunking utilities for TTS generation."""
import re

_nlp = None
_spacy_available = False


def _get_spacy_nlp():
    """Lazy-load spaCy with sentencizer for sentence splitting."""
    global _nlp, _spacy_available
    if _nlp is not None:
        return _nlp

    try:
        import spacy
        _nlp = spacy.blank("en")
        _nlp.add_pipe("sentencizer")
        _spacy_available = True
        print("[Chunking] spaCy sentencizer loaded")
    except ImportError:
        _spacy_available = False
        _nlp = None
    except Exception as exc:
        print(f"[Chunking] spaCy load error: {exc}")
        _spacy_available = False
        _nlp = None

    return _nlp


def split_into_sentences(text: str) -> list[str]:
    """Split text into sentences using spaCy when available, else regex."""
    nlp = _get_spacy_nlp()
    if nlp is None:
        return split_into_sentences_regex(text)

    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []

    doc = nlp(text)
    sentences = [sent.text.strip() for sent in doc.sents if sent.text.strip()]
    return sentences if sentences else [text]


def split_into_sentences_regex(text: str) -> list[str]:
    """Split text into sentences using regex fallback."""
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []

    sentences = re.split(r"(?<=[.!?])\s+", text)
    return [s.strip() for s in sentences if s.strip()]


def smart_chunk_text(text: str, max_chars: int = 1500) -> list[str]:
    """Split long text into chunks that respect sentence boundaries where possible."""
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []

    sentences = split_into_sentences(text)
    chunks: list[str] = []
    current_chunk: list[str] = []
    current_len = 0

    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue

        if len(sentence) > max_chars:
            if current_chunk:
                chunks.append(" ".join(current_chunk))
                current_chunk = []
                current_len = 0

            words = sentence.split()
            temp_chunk: list[str] = []
            temp_len = 0

            for word in words:
                if temp_len + len(word) + 1 > max_chars and temp_chunk:
                    chunks.append(" ".join(temp_chunk))
                    temp_chunk = [word]
                    temp_len = len(word)
                else:
                    temp_chunk.append(word)
                    temp_len += len(word) + (1 if temp_len else 0)

            if temp_chunk:
                chunks.append(" ".join(temp_chunk))
            continue

        if current_len + len(sentence) + (1 if current_len else 0) > max_chars and current_chunk:
            chunks.append(" ".join(current_chunk))
            current_chunk = [sentence]
            current_len = len(sentence)
        else:
            current_chunk.append(sentence)
            current_len += len(sentence) + (1 if current_len else 0)

    if current_chunk:
        chunks.append(" ".join(current_chunk))

    return chunks
