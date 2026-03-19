"""Regression tests for backend test-runtime isolation."""

from pathlib import Path

import database
import main


def test_backend_tests_use_isolated_runtime_paths():
    runtime_home = main._runtime_home.resolve()
    data_dir = main._runtime_data_dir.resolve()
    log_dir = main._log_dir.resolve()
    outputs_dir = main.outputs_dir.resolve()

    assert "mimika-backend-tests-" in str(runtime_home)
    assert data_dir == runtime_home / "data"
    assert log_dir == runtime_home / "logs"
    assert outputs_dir == runtime_home / "outputs"
    assert database.DB_PATH.resolve() == data_dir / "mimikastudio.db"
    assert main.PARENT_PID == 0


def test_backend_tests_log_inside_isolated_runtime():
    api_log = Path(main._api_log_path).resolve()

    assert "mimika-backend-tests-" in str(api_log)
    assert api_log.parent == main._log_dir.resolve()
