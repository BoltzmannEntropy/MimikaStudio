"""Emma IPA - British IPA-like transcription generator."""
import json
import re
from typing import Dict, Optional
from llm.factory import get_llm_provider

IPA_GENERATION_PROMPT = """Generate an **IPA-like British Transcription** for the given input text. The transcription must reflect articulate, rhythmic British pronunciation. Follow these rules:

**Phonetic Rules:**

1. **Bold Vowels:** Mark all vowel sounds in **bold**:
   - /æ/ as **A** (e.g., "cat" = K**A**T)
   - /e/ as **E** (e.g., "net" = N**E**T)
   - /ɪ/ as **I** (e.g., "sit" = S**I**T)
   - /ʌ/ as **U** (e.g., "cup" = K**U**P)
   - /ɒ/ as **O** (e.g., "hot" = H**O**T)
   - /aɪ/ as **EYE** (e.g., "my" = M**EYE**)
   - /ə/ as **ə** (e.g., "the" = th**ə**)
   - /ɜː/ as **ER** (e.g., "her" = H**ER**)
   - /ɔː/ as **AW** (e.g., "for" = F**AW**)
   - /uː/ as **OO** (e.g., "you" = Y**OO**)

2. **Non-rhotic Pronunciation:** Omit /r/ at syllable ends (e.g., "better" = BET-**ə**).

3. **Syllable Stress:** Mark stressed syllables in CAPS (e.g., "Vietnam" = V**EYE**-et-N**AH**M).

4. **Hyphenation:** Use hyphens to separate syllables (e.g., "radicalizing" = RAD-i-cal-**EYE**-zing).

5. **Consonant Clusters:** Break for clarity (e.g., "consistent" = kon-SIS-t**ə**nt).

**Example Input:**
For many, the experience of Vietnam had a radicalizing effect, leading them to conclude that US military intervention was not a well-intentioned mistake by policymakers, but part of a consistent effort to preserve American political, economic, and military domination globally, largely in service of corporate profits.

**Example Output:**
F**aw** M**A**-nee, th**ə** **ik-SPER-ee-əns** **əv** V**EYE**-et-n**ahm** H**AD** **ə** RAD-i-cal-**EYE**-zing **ə**-F**ECT**, L**EED**-ing them t**ə** kun-KL**OOD** that Y**OO**-**ES** MIL-it-ree in-t**ə**-VEN-sh**ən** W**UZ** naht **ə** WELL-in-T**EN**-sh**ənd** mis-T**AKE** by POL-i-see-MAKE-**əs**, b**ət** PAHT **əv** **ə** kon-SIS-t**ənt** EFF-**ət** t**ə** pre-ZERHV **ə**-M**ARE**-i-c**ən** PO-lit-i-c**əl**, ek-**ə**-NOM-ik, and MIL-it-ree dom-in-AY-sh**ən** GL**OAB**-**ə**-lee, LAHJ-lee in SER-vis **əv** KAWP-**ə**-rit PROFF-its.

---

Return ONLY the transcription in this exact JSON format:
{{"ipa": "..."}}

---

**Input Text:**

{text}
"""

SAMPLE_TEXT = """For many, the experience of Vietnam had a radicalizing effect, leading them to conclude that US military intervention was not a well-intentioned mistake by policymakers, but part of a consistent effort to preserve American political, economic, and military domination globally, largely in service of corporate profits. From this perspective, embraced by the "New Left"—as opposed to the old-line socialist and communist groups marginalized by the early 1950s—official rhetoric about freedom, democracy, and progress was seen as mere lip service."""


def generate_ipa_transcription(text: str, provider_name: Optional[str] = None, model: Optional[str] = None) -> Dict[str, str]:
    """Generate IPA-like British transcription using the configured LLM.

    Returns a dict with 'ipa' transcription.
    """
    provider = get_llm_provider(provider=provider_name, model=model)

    prompt = IPA_GENERATION_PROMPT.format(text=text)

    system_prompt = """You are an expert in British English phonetics and IPA transcription.
You generate IPA-like transcriptions that are readable and help learners understand British pronunciation.
Always use **bold** markers around vowel sounds as specified.
Return ONLY valid JSON with the transcription, no additional text or explanations."""

    response = provider.generate(prompt, system_prompt)

    # Clean up response - remove any markdown code blocks if present
    response = response.strip()
    if response.startswith("```"):
        lines = response.split("\n")
        # Remove first line (```json) and last line (```)
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        response = "\n".join(lines)

    response = response.strip()

    # Parse JSON response
    try:
        result = json.loads(response)
        ipa = result.get("ipa", "")
        return {
            "ipa": ipa,
            "version1": ipa  # Keep version1 for backward compatibility
        }
    except json.JSONDecodeError:
        # Fallback: return the whole response as IPA
        return {
            "ipa": response,
            "version1": response
        }


def get_sample_text() -> str:
    """Get the default sample text for IPA generation."""
    return SAMPLE_TEXT


def get_emma_ipa_samples() -> list:
    """Get all saved Emma IPA sample texts from the database."""
    from database import get_connection

    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, title, input_text, audio_file, is_default
        FROM emma_ipa_samples
        ORDER BY is_default DESC, id ASC
    """)
    rows = cursor.fetchall()
    conn.close()

    return [
        {
            "id": row[0],
            "title": row[1],
            "input_text": row[2],
            "audio_file": row[3],
            "is_default": bool(row[4])
        }
        for row in rows
    ]
