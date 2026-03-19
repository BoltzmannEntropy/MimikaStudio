"""Tests for backend parent-process watchdog cleanup."""

import main


class _SingleTickStopEvent:
    def __init__(self, *, stop_immediately: bool = False):
        self._stop_immediately = stop_immediately
        self.calls = 0

    def wait(self, timeout: float) -> bool:
        self.calls += 1
        return self._stop_immediately


def test_parent_watchdog_exits_when_parent_is_gone():
    exit_codes: list[int] = []

    def fake_exit(code: int) -> None:
        exit_codes.append(code)

    stop_event = _SingleTickStopEvent()
    main._watch_parent_process(
        4242,
        stop_event,
        process_exists=lambda pid: False,
        exit_process=fake_exit,
        wait_seconds=0,
    )

    assert stop_event.calls == 1
    assert exit_codes == [0]


def test_parent_watchdog_stops_cleanly_without_exiting():
    exit_codes: list[int] = []

    def fake_exit(code: int) -> None:
        exit_codes.append(code)

    stop_event = _SingleTickStopEvent(stop_immediately=True)
    main._watch_parent_process(
        4242,
        stop_event,
        process_exists=lambda pid: False,
        exit_process=fake_exit,
        wait_seconds=0,
    )

    assert stop_event.calls == 1
    assert exit_codes == []
