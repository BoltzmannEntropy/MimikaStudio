from __future__ import annotations

from pathlib import Path


def _read_sidecar_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def get_bundled_pregenerated_samples(pregen_dir: Path) -> list[dict[str, str]]:
    samples: list[dict[str, str]] = [
        {
            "engine": "qwen3",
            "voice": "Yelena",
            "title": "Genesis 4 Preview (Yelena)",
            "description": "Qwen3 voice clone demo using Genesis 4:6-7",
            "relative_path": "qwen3/qwen3-yelena-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen? If thou doest "
                "well, shalt thou not be accepted? and if thou doest not well, sin "
                "lieth at the door."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Svetlana",
            "title": "Genesis 4 Preview (Svetlana)",
            "description": "Qwen3 voice clone demo using Genesis 4:6-7",
            "relative_path": "qwen3/qwen3-svetlana-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen? If thou doest "
                "well, shalt thou not be accepted? and if thou doest not well, sin "
                "lieth at the door."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Ryan",
            "title": "Genesis 4 Preview (Ryan)",
            "description": "Qwen3 preset speaker demo using Genesis 4",
            "relative_path": "qwen3/qwen3-ryan-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 8 and 9: And Cain talked with Abel his "
                "brother: and it came to pass, when they were in the field, that Cain "
                "rose up against Abel his brother, and slew him."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Yelena",
            "title": "Hebrew Preview (Yelena)",
            "description": "Cross-language Qwen3 clone demo in Hebrew",
            "relative_path": "qwen3/qwen3-yelena-hebrew-demo.wav",
            "text_sidecar": "qwen3/qwen3-yelena-hebrew-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Alistair",
            "title": "Genesis 1 Preview (Alistair, English)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-alistair-english-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-alistair-english-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Alistair",
            "title": "Genesis 1 Preview (Alistair, Spanish)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-alistair-spanish-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-alistair-spanish-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Anastasia",
            "title": "Genesis 1 Preview (Anastasia, Chinese)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-anastasia-chinese-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-anastasia-chinese-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Anastasia",
            "title": "Genesis 1 Preview (Anastasia, Italian)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-anastasia-italian-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-anastasia-italian-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Beatrice",
            "title": "Genesis 1 Preview (Beatrice, Japanese)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-beatrice-japanese-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-beatrice-japanese-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Eleanor",
            "title": "Genesis 1 Preview (Eleanor, Korean)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-eleanor-korean-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-eleanor-korean-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Harriet",
            "title": "Genesis 1 Preview (Harriet, German)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-harriet-german-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-harriet-german-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Mikhail",
            "title": "Genesis 1 Preview (Mikhail, French)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-mikhail-french-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-mikhail-french-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Svetlana",
            "title": "Genesis 1 Preview (Svetlana, Russian)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-svetlana-russian-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-svetlana-russian-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Yelena",
            "title": "Genesis 1 Preview (Yelena, Portuguese)",
            "description": "Qwen3 supported-language showcase",
            "relative_path": "qwen3/qwen3-yelena-portuguese-genesis1-demo.wav",
            "text_sidecar": "qwen3/qwen3-yelena-portuguese-genesis1-demo.txt",
        },
        {
            "engine": "qwen3",
            "voice": "Yelena",
            "title": "Sherlock Long-Form Audiobook (Yelena)",
            "description": "A Scandal in Bohemia voice-cloned narration, 43m 20s",
            "relative_path": "audiobooks/long-sherlock-yelena.mp3",
            "text": (
                "Full Sherlock Holmes chapter with Yelena's cloned voice, natural "
                "pacing, and expressive long-form narration."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Mikhail",
            "title": "Sherlock Long-Form Audiobook (Mikhail)",
            "description": "A Scandal in Bohemia voice-cloned narration, 45m 36s",
            "relative_path": "audiobooks/long-sherlock-mikhail.mp3",
            "text": (
                "Full Sherlock Holmes chapter with Mikhail's cloned voice and "
                "expressive male narration."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Anastasia",
            "title": "Sherlock Long-Form Audiobook (Anastasia)",
            "description": "A Scandal in Bohemia voice-cloned narration, 43m 40s",
            "relative_path": "audiobooks/long-sherlock-anastasia.mp3",
            "text": (
                "Full Sherlock Holmes chapter with Anastasia's cloned voice and a "
                "refined vocal character."
            ),
        },
        {
            "engine": "qwen3",
            "voice": "Svetlana",
            "title": "Sherlock Long-Form Audiobook (Svetlana)",
            "description": "A Scandal in Bohemia voice-cloned narration, 43m 55s",
            "relative_path": "audiobooks/long-sherlock-svetlana.mp3",
            "text": (
                "Full Sherlock Holmes chapter with Svetlana's cloned voice, warm "
                "narration, and distinctive timbre."
            ),
        },
        {
            "engine": "chatterbox",
            "voice": "Yelena",
            "title": "Genesis 5 Expressive Demo (Yelena)",
            "description": "Emotional Chatterbox clone demo",
            "relative_path": "chatterbox/chatterbox-yelena-demo-1770830814.wav",
            "text": (
                "Genesis chapter 5 baseline rendered with emotional Chatterbox voice "
                "cloning using Yelena."
            ),
        },
        {
            "engine": "chatterbox",
            "voice": "Svetlana",
            "title": "Genesis 5 Expressive Demo (Svetlana)",
            "description": "Emotional Chatterbox clone demo",
            "relative_path": "chatterbox/chatterbox-svetlana-demo-1770830815.wav",
            "text": (
                "Genesis chapter 5 baseline rendered with emotional Chatterbox voice "
                "cloning using Svetlana."
            ),
        },
        {
            "engine": "supertonic",
            "voice": "F1",
            "title": "Genesis 4 Preview (F1)",
            "description": "Supertonic F1 English preview for instant playback",
            "relative_path": "supertonic/supertonic-f1-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen?"
            ),
        },
        {
            "engine": "supertonic",
            "voice": "M2",
            "title": "Genesis 4 Preview (M2)",
            "description": "Supertonic M2 English preview using Genesis 4:8-9",
            "relative_path": "supertonic/supertonic-m2-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 8 and 9: And Cain talked with Abel his "
                "brother: and it came to pass, when they were in the field, that Cain "
                "rose up against Abel his brother, and slew him."
            ),
        },
        {
            "engine": "cosyvoice3",
            "voice": "F1",
            "title": "Genesis 4 Preview (F1)",
            "description": "CosyVoice3 F1 multilingual preview",
            "relative_path": "cosyvoice3/cosyvoice3-f1-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, "
                "Why art thou wroth? and why is thy countenance fallen?"
            ),
        },
        {
            "engine": "cosyvoice3",
            "voice": "M2",
            "title": "Genesis 4 Preview (M2)",
            "description": "CosyVoice3 M2 multilingual preview",
            "relative_path": "cosyvoice3/cosyvoice3-m2-genesis4-demo.wav",
            "text": (
                "Genesis chapter 4, verses 8 and 9: And Cain talked with Abel his "
                "brother: and it came to pass, when they were in the field, that Cain "
                "rose up against Abel his brother, and slew him."
            ),
        },
        {
            "engine": "kokoro",
            "voice": "bf_emma",
            "title": "Meditations Long-Form Audiobook (Emma)",
            "description": "Marcus Aurelius excerpt narrated by Emma, 12m 28s",
            "relative_path": "audiobooks/long-meditations-emma.mp3",
            "text": (
                "Marcus Aurelius' Meditations excerpt narrated with Emma's crisp "
                "British accent at 0.95x speed."
            ),
        },
        {
            "engine": "kokoro",
            "voice": "bm_george",
            "title": "Meditations Long-Form Audiobook (George)",
            "description": "Marcus Aurelius excerpt narrated by George, 13m 36s",
            "relative_path": "audiobooks/long-meditations-george.mp3",
            "text": (
                "Marcus Aurelius' Meditations excerpt narrated with George's "
                "grounded British tone at 0.95x speed."
            ),
        },
    ]

    resolved: list[dict[str, str]] = []
    for sample in samples:
        file_path = pregen_dir / sample["relative_path"]
        text = sample.get("text", "").strip()
        text_sidecar = sample.get("text_sidecar")
        if text_sidecar:
            sidecar_text = _read_sidecar_text(pregen_dir / text_sidecar)
            if sidecar_text:
                text = sidecar_text
        resolved.append(
            {
                "engine": sample["engine"],
                "voice": sample["voice"],
                "title": sample["title"],
                "description": sample["description"],
                "text": text,
                "file_path": str(file_path),
                "relative_path": sample["relative_path"],
            }
        )

    return resolved
