#!/usr/bin/env python3
"""Single-process Qwen3 clone benchmark for Mimika Python engine."""
from __future__ import annotations

import argparse
import csv
import gc
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from tts.qwen3_engine import GenerationParams, Qwen3TTSEngine  # noqa: E402

try:
    import psutil  # type: ignore
except Exception:  # pragma: no cover
    psutil = None


@dataclass
class BenchCase:
    voice: str
    ref_audio_path: str
    ref_text: str
    prompt_name: str
    text: str


def current_rss_mb() -> float:
    if psutil is None:
        return -1.0
    proc = psutil.Process(os.getpid())
    return proc.memory_info().rss / (1024.0 * 1024.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--max-tokens", type=int, default=8)
    parser.add_argument("--models", type=str, default="0.6B,1.7B")
    parser.add_argument(
        "--natasha-ref",
        type=str,
        default=str(ROOT / "backend" / "data" / "samples" / "voices" / "Natasha.wav"),
    )
    parser.add_argument(
        "--suzan-ref",
        type=str,
        default=str(ROOT / "backend" / "data" / "samples" / "voices" / "Suzan.wav"),
    )
    parser.add_argument("--cleanup-output", action="store_true")
    return parser.parse_args()


def format_float(value: float) -> str:
    return f"{value:.4f}"


def main() -> int:
    args = parse_args()
    run_count = max(1, args.runs)
    max_tokens = max(1, args.max_tokens)
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    if not models:
        models = ["0.6B", "1.7B"]

    for ref in (args.natasha_ref, args.suzan_ref):
        if not Path(ref).exists():
            raise FileNotFoundError(f"Missing reference audio: {ref}")

    short_text = "This is a Swift Qwen3 clone verification sample."
    genesis_text = (
        "Genesis chapter 5, verses 1 through 3: This is the book of the generations of Adam. "
        "In the day that God created man, in the likeness of God made he him; male and female created he them."
    )
    natasha_ref_text = "Hello, this is the Natasha reference sample used for clone testing."
    suzan_ref_text = "Hello, this is the Suzan reference sample used for clone testing."

    cases = [
        BenchCase("natasha", args.natasha_ref, natasha_ref_text, "short", short_text),
        BenchCase("natasha", args.natasha_ref, natasha_ref_text, "genesis5", genesis_text),
        BenchCase("suzan", args.suzan_ref, suzan_ref_text, "short", short_text),
        BenchCase("suzan", args.suzan_ref, suzan_ref_text, "genesis5", genesis_text),
    ]

    generation_params = GenerationParams(
        temperature=0.9,
        top_p=1.0,
        top_k=50,
        repetition_penalty=1.05,
        max_new_tokens=max_tokens,
        do_sample=True,
        seed=1234,
    )

    report_dir = ROOT / "backend" / "outputs" / "benchmarks"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"qwen3_python_clone_bench_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

    with report_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "model_size",
                "voice",
                "prompt",
                "run",
                "init_sec",
                "wall_sec",
                "audio_sec",
                "rss_mb",
                "output",
            ]
        )

        for model_size in models:
            print(f"=== Model {model_size} initialize ===")
            engine = Qwen3TTSEngine(model_size=model_size, mode="clone", quantization="bf16")

            init_start = time.perf_counter()
            engine.load_model()
            init_sec = time.perf_counter() - init_start
            print(f"Initialized in {init_sec:.2f}s (RSS {current_rss_mb():.1f} MB)")

            for run_index in range(1, run_count + 1):
                for case in cases:
                    start = time.perf_counter()
                    output_path = engine.generate_voice_clone(
                        text=case.text,
                        ref_audio_path=case.ref_audio_path,
                        ref_text=case.ref_text,
                        language="English",
                        speed=1.0,
                        params=generation_params,
                    )
                    wall_sec = time.perf_counter() - start
                    info = sf.info(str(output_path))
                    audio_sec = info.duration
                    rss_mb = current_rss_mb()

                    print(
                        "model=%s run=%d voice=%s prompt=%s wall=%.2fs audio=%.2fs rss=%.1fMB"
                        % (model_size, run_index, case.voice, case.prompt_name, wall_sec, audio_sec, rss_mb)
                    )
                    writer.writerow(
                        [
                            model_size,
                            case.voice,
                            case.prompt_name,
                            run_index,
                            format_float(init_sec),
                            format_float(wall_sec),
                            format_float(audio_sec),
                            format_float(rss_mb),
                            str(output_path),
                        ]
                    )
                    handle.flush()

                    if args.cleanup_output:
                        try:
                            Path(output_path).unlink(missing_ok=True)
                        except Exception:
                            pass

            engine.unload()
            del engine
            gc.collect()

    print(f"REPORT={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
