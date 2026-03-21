from tts import text_chunking


class _FakeSpan:
    def __init__(self, text: str):
        self.text = text


class _FakeDoc:
    def __init__(self, sentences: list[str]):
        self.sents = [_FakeSpan(sentence) for sentence in sentences]


class _LengthGuardNlp:
    def __init__(self, max_length: int):
        self.max_length = max_length
        self.calls = 0

    def __call__(self, _text: str):
        self.calls += 1
        return _FakeDoc(["should not be used"])


class _E088Nlp:
    def __init__(self, max_length: int = 1_000_000):
        self.max_length = max_length

    def __call__(self, text: str):
        raise ValueError(
            f"[E088] Text of length {len(text)} exceeds maximum of {self.max_length}."
        )


def test_split_into_sentences_falls_back_to_regex_when_text_exceeds_spacy_limit(
    monkeypatch,
):
    fake_nlp = _LengthGuardNlp(max_length=10)
    monkeypatch.setattr(text_chunking, "_nlp", fake_nlp)
    monkeypatch.setattr(text_chunking, "_spacy_available", True)

    sentences = text_chunking.split_into_sentences(
        "First sentence. Second sentence. Third sentence."
    )

    assert fake_nlp.calls == 0
    assert sentences == ["First sentence.", "Second sentence.", "Third sentence."]


def test_split_into_sentences_falls_back_to_regex_when_spacy_raises_e088(
    monkeypatch,
):
    monkeypatch.setattr(text_chunking, "_nlp", _E088Nlp())
    monkeypatch.setattr(text_chunking, "_spacy_available", True)

    sentences = text_chunking.split_into_sentences(
        "First sentence. Second sentence. Third sentence."
    )

    assert sentences == ["First sentence.", "Second sentence.", "Third sentence."]
