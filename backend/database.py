import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "data" / "mimikastudio.db"

def get_connection():
    # Use one connection per caller/thread; avoid cross-thread reuse hazards.
    return sqlite3.connect(DB_PATH, timeout=30)

def init_db():
    """Initialize database schema."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection()
    cursor = conn.cursor()

    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS sample_texts (
            id INTEGER PRIMARY KEY,
            engine TEXT NOT NULL,
            text TEXT NOT NULL,
            language TEXT DEFAULT 'en',
            category TEXT DEFAULT 'general'
        );

        CREATE TABLE IF NOT EXISTS kokoro_voices (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            gender TEXT NOT NULL,
            quality_grade TEXT,
            is_british INTEGER DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS language_content (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            content_type TEXT NOT NULL,
            content_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS pregenerated_samples (
            id INTEGER PRIMARY KEY,
            engine TEXT NOT NULL,
            voice TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT,
            text TEXT NOT NULL,
            file_path TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS emma_ipa_samples (
            id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            input_text TEXT NOT NULL,
            audio_file TEXT,
            is_default INTEGER DEFAULT 0,
            version1_ipa TEXT,
            version2_ipa TEXT
        );

        CREATE TABLE IF NOT EXISTS emma_ipa_outputs (
            id INTEGER PRIMARY KEY,
            sample_id INTEGER,
            input_text TEXT NOT NULL,
            version1_ipa TEXT,
            version2_ipa TEXT,
            llm_provider TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (sample_id) REFERENCES emma_ipa_samples(id)
        );

        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS license_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            license_key TEXT,
            email TEXT,
            activated_at TIMESTAMP,
            last_validated TIMESTAMP,
            is_valid INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS trial_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            expires_at TIMESTAMP
        );
    """)
    conn.commit()
    conn.close()

def seed_db():
    """Seed database with initial data."""
    conn = get_connection()
    cursor = conn.cursor()

    # Check if already seeded
    cursor.execute("SELECT COUNT(*) FROM kokoro_voices")
    if cursor.fetchone()[0] > 0:
        conn.close()
        return

    # Seed Kokoro British voices
    british_voices = [
        ("bf_emma", "Emma", "female", "B-"),
        ("bf_alice", "Alice", "female", "D"),
        ("bf_isabella", "Isabella", "female", "C"),
        ("bf_lily", "Lily", "female", "D"),
        ("bm_daniel", "Daniel", "male", "D"),
        ("bm_fable", "Fable", "male", "C"),
        ("bm_george", "George", "male", "C"),
        ("bm_lewis", "Lewis", "male", "D+"),
    ]
    cursor.executemany(
        "INSERT INTO kokoro_voices (code, name, gender, quality_grade) VALUES (?, ?, ?, ?)",
        british_voices
    )

    # Seed sample texts
    sample_texts = [
        ("kokoro", "Good morning! The weather today is absolutely splendid.", "en", "greeting"),
        ("kokoro", "I'd be delighted to help you with that inquiry.", "en", "polite"),
        ("kokoro", "The British Museum houses an extraordinary collection of artifacts.", "en", "culture"),
        ("kokoro", "Would you fancy a cup of tea? It's freshly brewed.", "en", "casual"),
    ]
    cursor.executemany(
        "INSERT INTO sample_texts (engine, text, language, category) VALUES (?, ?, ?, ?)",
        sample_texts
    )

    # Seed pregenerated samples
    pregen_dir = Path(__file__).parent / "data" / "pregenerated"
    if pregen_dir.exists():
        pregenerated_samples = [
            (
                "kokoro",
                "bf_lily",
                "Nuclear Policy Analysis",
                "Geopolitical analysis on Russia's nuclear posture - Lily voice",
                """Russia's nuclear pivot is best understood as a response to geographic insecurity: compressed warning times, limited strategic depth, and constrained maritime access create acute pressure in crises. Treating nuclear signaling as a substitute for conventional resilience, however, introduces severe instability. Compressed decision cycles and ambiguous indications leave little room for interpretation, and the historical record of accidents and false alarms shows that such conditions are a poor foundation for deterrence. When the instrument of policy with the most irreversible consequences is moved downward into earlier stages of escalation, the central danger becomes misreading rather than intent.""",
                str(pregen_dir / "kokoro-lily-nuclear-policy.wav")
            ),
            (
                "qwen3",
                "Natasha",
                "Genesis 4 Preview (Natasha)",
                "Qwen3 voice preview using Genesis 4:6-7 for voice cloning reference",
                """Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, Why art thou wroth? and why is thy countenance fallen? If thou doest well, shalt thou not be accepted? and if thou doest not well, sin lieth at the door.""",
                str(pregen_dir / "qwen3-natasha-genesis4-demo.wav")
            ),
            (
                "qwen3",
                "Suzan",
                "Genesis 4 Preview (Suzan)",
                "Qwen3 voice preview using Genesis 4:6-7 for voice cloning reference",
                """Genesis chapter 4, verses 6 and 7: And the Lord said unto Cain, Why art thou wroth? and why is thy countenance fallen? If thou doest well, shalt thou not be accepted? and if thou doest not well, sin lieth at the door.""",
                str(pregen_dir / "qwen3-suzan-genesis4-demo.wav")
            ),
        ]
        for sample in pregenerated_samples:
            if Path(sample[5]).exists():
                cursor.execute(
                    "INSERT OR IGNORE INTO pregenerated_samples (engine, voice, title, description, text, file_path) VALUES (?, ?, ?, ?, ?, ?)",
                    sample
                )

    # Seed Emma IPA samples with preloaded IPA transcriptions
    emma_ipa_sample_text = """For many, the experience of Vietnam had a radicalizing effect, leading them to conclude that US military intervention was not a well-intentioned mistake by policymakers, but part of a consistent effort to preserve American political, economic, and military domination globally, largely in service of corporate profits. From this perspective, embraced by the "New Left"—as opposed to the old-line socialist and communist groups marginalized by the early 1950s—official rhetoric about freedom, democracy, and progress was seen as mere lip service."""

    emma_ipa_version1 = """F**aw** M**A**-nee, th**ə** **ik-SPER-ee-əns** **əv** V**EYE**-et-n**ahm** H**AD** **ə** RAD-i-cal-**EYE**-zing **ə**-F**ECT**, L**EED**-ing them t**ə** kun-KL**OOD** that Y**OO**-**ES** MIL-it-ree in-t**ə**-VEN-sh**ən** W**UZ** naht **ə** WELL-in-T**EN**-sh**ənd** mis-T**AKE** by POL-i-see-MAKE-**əs**, b**ət** PAHT **əv** **ə** kon-SIS-t**ənt** EFF-**ət** t**ə** pre-ZERHV **ə**-M**ARE**-i-c**ən** PO-lit-i-c**əl**, ek-**ə**-NOM-ik, and MIL-it-ree dom-in-AY-sh**ən** GL**OAB**-**ə**-lee, LAHJ-lee in SER-vis **əv** KAWP-**ə**-rit PROFF-its.

Fr**awm** this pur-SPEK-tiv, em-BR**AY**ST by th**ə** "NY**OO** left"—**az** **ə**-POHZD t**ə** thee OHLD-lien SOH-sh**ə**-list and KOM-yoo-nist GROOPS MAR-jin-**ə**-LIEZD by thee ER-lee FIFT-eez—uh-FISH-ul RET-or-ik **ə**-BAWT FREE-d**ə**m, dih-MOK-r**ə**-see, and PROG-res WUZ SEEN **ə**z meer LIP-SER-vis."""

    emma_ipa_version2 = """**Faw MA-nee**, thə **ik-SPER-ee-əns** əv **VIE-et-nahm** HAD ə **RAD-i-cal-eye-zing ə-FECT**, **LEED-ing** them tə **kun-KLOOD** that **YOO-ES MIL-it-ree in-tə-VEN-shən** WUZ naht ə **WELL-in-TEN-shənd** mis-TAKE by **POL-i-see-MAKE-əs**, bət **PAHT** əv ə **kon-SIS-tənt EFF-ət** tə **pre-ZERHV ə-MARE-i-cən PO-lit-i-cəl**, **ek-ə-NOM-ik**, and **MIL-it-ree dom-in-AY-shən GLOBE-ə-lee**, **LAHJ-lee** in **SER-vis** əv **KAWP-ə-rit PROFF-its**.

**Frawm this pur-SPEK-tiv**, **em-BRAYST** by thə **"NYOO left"—az ə-POHZD tə thee OHLD-lien SOH-shə-list and KOM-yoo-nist GROOPS MAR-jin-ə-LIEZD by thee ER-lee FIFT-eez**—uh-FISH-ul **RET-or-ik** ə-BAWT **FREE-dəm**, **dih-MOK-rə-see**, and **PROG-res** WUZ SEEN əz meer **LIP-SER-vis**."""

    emma_ipa_audio_path = str(pregen_dir / "emma-ipa-lily-sample.wav")
    cursor.execute(
        "INSERT OR IGNORE INTO emma_ipa_samples (id, title, input_text, audio_file, is_default, version1_ipa, version2_ipa) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (1, "Vietnam History Example", emma_ipa_sample_text, emma_ipa_audio_path, 1, emma_ipa_version1, emma_ipa_version2)
    )

    # Add additional Emma IPA sample texts
    additional_samples = [
        (2, "British Weather", "The weather in London today is absolutely splendid, with clear skies and a gentle breeze coming from the west. One might even consider taking a leisurely stroll through Hyde Park.", None, 0, None, None),
        (3, "Tea Time", "Would you care for a cup of tea? I've just put the kettle on, and we have some lovely biscuits from the bakery down the road.", None, 0, None, None),
    ]
    cursor.executemany(
        "INSERT OR IGNORE INTO emma_ipa_samples (id, title, input_text, audio_file, is_default, version1_ipa, version2_ipa) VALUES (?, ?, ?, ?, ?, ?, ?)",
        additional_samples
    )

    # Seed default settings
    default_settings = [
        ("output_folder", str(Path.home() / "MimikaStudio" / "outputs")),
        ("theme", "system"),
        ("auto_update", "true"),
        ("update_frequency", "weekly"),
    ]
    cursor.executemany(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES (?, ?)",
        default_settings
    )

    conn.commit()
    conn.close()
    print("Database seeded successfully.")


if __name__ == "__main__":
    init_db()
    seed_db()
