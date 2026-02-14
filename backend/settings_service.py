"""Settings management service."""
from pathlib import Path
from database import get_connection
from datetime import datetime


def _ensure_folder(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def get_setting(key: str) -> str | None:
    """Get a setting value by key."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM app_settings WHERE key = ?", (key,))
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def set_setting(key: str, value: str) -> bool:
    """Set a setting value."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """INSERT INTO app_settings (key, value, updated_at)
           VALUES (?, ?, ?)
           ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?""",
        (key, value, datetime.now(), value, datetime.now())
    )
    conn.commit()
    conn.close()
    return True

def get_all_settings() -> dict:
    """Get all settings as a dictionary."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT key, value FROM app_settings")
    rows = cursor.fetchall()
    conn.close()
    return {row[0]: row[1] for row in rows}

def get_output_folder() -> str:
    """Get the output folder path, creating it if needed."""
    folder = get_setting("output_folder")
    if folder:
        try:
            return str(_ensure_folder(Path(folder).expanduser()))
        except OSError:
            pass

    default = Path.home() / "MimikaStudio" / "outputs"
    return str(_ensure_folder(default))

def set_output_folder(path: str) -> bool:
    """Set the output folder path."""
    normalized = (path or "").strip()
    if not normalized:
        raise OSError("output folder path cannot be empty")
    folder = Path(normalized).expanduser()
    _ensure_folder(folder)
    return set_setting("output_folder", str(folder))
