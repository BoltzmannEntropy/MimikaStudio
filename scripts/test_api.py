#!/usr/bin/env python3
"""
Full API test script for MimikaStudio backend.
Run with: python scripts/test_api.py
Requires backend running on localhost:8000
"""

import requests
import sys

BASE_URL = "http://localhost:8000"

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'

def print_test(name: str, passed: bool, details: str = ""):
    status = f"{Colors.GREEN}PASS{Colors.END}" if passed else f"{Colors.RED}FAIL{Colors.END}"
    print(f"  [{status}] {name}")
    if details and not passed:
        print(f"         {Colors.YELLOW}{details}{Colors.END}")

def test_health():
    """Test health endpoint."""
    print(f"\n{Colors.BLUE}=== Health Check ==={Colors.END}")
    try:
        r = requests.get(f"{BASE_URL}/api/health")
        passed = r.status_code == 200 and r.json().get("status") == "ok"
        print_test("GET /api/health", passed, r.text)
        return passed
    except Exception as e:
        print_test("GET /api/health", False, str(e))
        return False


def test_kokoro_voices():
    """Test Kokoro voices listing."""
    print(f"\n{Colors.BLUE}=== Kokoro Voices ==={Colors.END}")
    try:
        r = requests.get(f"{BASE_URL}/api/kokoro/voices")
        data = r.json()
        passed = r.status_code == 200 and "voices" in data
        print_test("GET /api/kokoro/voices", passed, f"Found {len(data.get('voices', []))} voices, default={data.get('default')}")

        if passed:
            for v in data["voices"]:
                default_mark = " (default)" if v.get("is_default") else ""
                print(f"         - {v['code']}: {v['name']} ({v['gender']}, grade {v['grade']}){default_mark}")

        return passed, data.get("default")
    except Exception as e:
        print_test("GET /api/kokoro/voices", False, str(e))
        return False, None

def test_kokoro_generate(voice: str):
    """Test Kokoro generation."""
    print(f"\n{Colors.BLUE}=== Kokoro Generation ==={Colors.END}")
    try:
        payload = {
            "text": "Good morning! The weather today is absolutely splendid.",
            "voice": voice,
            "speed": 1.0
        }
        r = requests.post(f"{BASE_URL}/api/kokoro/generate", json=payload)
        data = r.json()
        passed = r.status_code == 200 and "audio_url" in data
        print_test(f"POST /api/kokoro/generate (voice={voice})", passed, data.get("audio_url", r.text))
        return passed, data.get("audio_url")
    except Exception as e:
        print_test("POST /api/kokoro/generate", False, str(e))
        return False, None

def test_language_stories():
    """Test language content listing."""
    print(f"\n{Colors.BLUE}=== Language Content ==={Colors.END}")
    try:
        r = requests.get(f"{BASE_URL}/api/language/stories")
        data = r.json()
        passed = r.status_code == 200 and "stories" in data
        print_test("GET /api/language/stories", passed, f"Found {len(data.get('stories', []))} stories")

        story_id = None
        if passed and data["stories"]:
            for s in data["stories"]:
                print(f"         - [{s['id']}] {s['title']} ({s['type']})")
            story_id = data["stories"][0]["id"]

        return passed, story_id
    except Exception as e:
        print_test("GET /api/language/stories", False, str(e))
        return False, None

def test_language_story(story_id: int):
    """Test getting a specific story."""
    try:
        r = requests.get(f"{BASE_URL}/api/language/story/{story_id}")
        data = r.json()
        passed = r.status_code == 200 and "lines" in data
        line_count = len(data.get("lines", []))
        print_test(f"GET /api/language/story/{story_id}", passed, f"Title: {data.get('title')}, Lines: {line_count}")

        if passed and data["lines"]:
            line = data["lines"][0]
            print(f"         Sample line:")
            print(f"           Native: {line.get('native')}")
            print(f"           Translit: {line.get('transliteration')}")
            print(f"           Natural: {line.get('natural')}")

        return passed
    except Exception as e:
        print_test(f"GET /api/language/story/{story_id}", False, str(e))
        return False

def test_samples():
    """Test sample texts endpoints."""
    print(f"\n{Colors.BLUE}=== Sample Texts ==={Colors.END}")
    all_passed = True

    for engine in ["kokoro"]:
        try:
            r = requests.get(f"{BASE_URL}/api/samples/{engine}")
            data = r.json()
            passed = r.status_code == 200 and "samples" in data
            sample_count = len(data.get("samples", []))
            print_test(f"GET /api/samples/{engine}", passed, f"Found {sample_count} samples")
            all_passed = all_passed and passed
        except Exception as e:
            print_test(f"GET /api/samples/{engine}", False, str(e))
            all_passed = False

    return all_passed

def test_audio_access(audio_url: str):
    """Test that generated audio is accessible."""
    if not audio_url:
        return False
    try:
        r = requests.get(f"{BASE_URL}{audio_url}")
        passed = r.status_code == 200 and len(r.content) > 0
        print_test(f"GET {audio_url}", passed, f"Size: {len(r.content)} bytes")
        return passed
    except Exception as e:
        print_test(f"GET {audio_url}", False, str(e))
        return False

def main():
    print(f"{Colors.BLUE}{'='*50}{Colors.END}")
    print(f"{Colors.BLUE}       MimikaStudio API Test Suite{Colors.END}")
    print(f"{Colors.BLUE}{'='*50}{Colors.END}")

    results = []

    # Health check first
    if not test_health():
        print(f"\n{Colors.RED}Backend not running! Start with: tssctl up{Colors.END}")
        sys.exit(1)
    results.append(True)

    # Kokoro tests
    passed, default_voice = test_kokoro_voices()
    results.append(passed)

    if default_voice:
        passed, audio_url = test_kokoro_generate(default_voice)
        results.append(passed)
        if audio_url:
            results.append(test_audio_access(audio_url))

    # Language content tests
    passed, story_id = test_language_stories()
    results.append(passed)

    if story_id:
        results.append(test_language_story(story_id))

    # Sample texts tests
    results.append(test_samples())

    # Summary
    passed_count = sum(results)
    total_count = len(results)
    print(f"\n{Colors.BLUE}{'='*50}{Colors.END}")
    print(f"Results: {passed_count}/{total_count} tests passed")

    if passed_count == total_count:
        print(f"{Colors.GREEN}All tests passed!{Colors.END}")
        sys.exit(0)
    else:
        print(f"{Colors.RED}Some tests failed.{Colors.END}")
        sys.exit(1)

if __name__ == "__main__":
    main()
