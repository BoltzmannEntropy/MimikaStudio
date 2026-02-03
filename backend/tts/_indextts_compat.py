"""Compatibility shim for IndexTTS-2 with transformers >= 4.57.

IndexTTS-2 was built against transformers 4.52.x and imports several symbols
that were removed or renamed in 4.57+.  This module patches the affected
transformers sub-modules so that IndexTTS can be imported without error.

Call ``apply()`` **before** ``import indextts``.
"""

from __future__ import annotations

import importlib
import logging

logger = logging.getLogger(__name__)


def apply() -> None:
    """Patch transformers modules for IndexTTS-2 compatibility."""
    _patch_cache_utils()
    _patch_configuration_utils()
    _patch_candidate_generator()
    _patch_sequence_summary()
    logger.info("IndexTTS-2 transformers compatibility patches applied")


# ---------------------------------------------------------------------------
# 1.  QuantizedCacheConfig  (removed in transformers >= 4.57)
# ---------------------------------------------------------------------------
def _patch_cache_utils() -> None:
    import transformers.cache_utils as cu

    if hasattr(cu, "QuantizedCacheConfig"):
        return  # already present (older transformers) – nothing to do

    from dataclasses import dataclass, field
    from typing import Optional

    @dataclass
    class QuantizedCacheConfig:
        """Minimal stand-in for the removed QuantizedCacheConfig."""
        backend: str = "quanto"
        nbits: int = 4
        axis_key: int = 0
        axis_value: int = 0
        q_group_size: int = 64
        residual_length: int = 128
        compute_dtype: Optional[object] = None
        device: Optional[str] = None

    cu.QuantizedCacheConfig = QuantizedCacheConfig  # type: ignore[attr-defined]
    logger.debug("Patched transformers.cache_utils.QuantizedCacheConfig")


# ---------------------------------------------------------------------------
# 2.  NEED_SETUP_CACHE_CLASSES_MAPPING / QUANT_BACKEND_CLASSES_MAPPING
#     (removed in transformers >= 4.57)
# ---------------------------------------------------------------------------
def _patch_configuration_utils() -> None:
    import transformers.generation.configuration_utils as gu

    if not hasattr(gu, "NEED_SETUP_CACHE_CLASSES_MAPPING"):
        from transformers.cache_utils import (
            DynamicCache,
            HQQQuantizedCache,
            OffloadedCache,
            QuantoQuantizedCache,
            StaticCache,
            SlidingWindowCache,
        )

        # Try to import optional cache classes that may or may not exist
        _optional = {}
        for name in ("HybridCache", "OffloadedStaticCache"):
            cls = getattr(importlib.import_module("transformers.cache_utils"), name, None)
            if cls is not None:
                _optional[name] = cls

        mapping: dict = {
            "static": StaticCache,
            "sliding_window": SlidingWindowCache,
        }
        if "HybridCache" in _optional:
            mapping["hybrid"] = _optional["HybridCache"]
        if "OffloadedStaticCache" in _optional:
            mapping["offloaded_static"] = _optional["OffloadedStaticCache"]

        gu.NEED_SETUP_CACHE_CLASSES_MAPPING = mapping  # type: ignore[attr-defined]
        logger.debug("Patched NEED_SETUP_CACHE_CLASSES_MAPPING")

    if not hasattr(gu, "QUANT_BACKEND_CLASSES_MAPPING"):
        from transformers.cache_utils import (
            HQQQuantizedCache,
            QuantoQuantizedCache,
        )

        gu.QUANT_BACKEND_CLASSES_MAPPING = {  # type: ignore[attr-defined]
            "quanto": QuantoQuantizedCache,
            "HQQ": HQQQuantizedCache,
        }
        logger.debug("Patched QUANT_BACKEND_CLASSES_MAPPING")


# ---------------------------------------------------------------------------
# 3.  _crop_past_key_values  (removed from candidate_generator in 4.57)
# ---------------------------------------------------------------------------
def _patch_candidate_generator() -> None:
    import transformers.generation.candidate_generator as cg

    if hasattr(cg, "_crop_past_key_values"):
        return

    from transformers.cache_utils import DynamicCache

    def _crop_past_key_values(model, past_key_values, new_cache_size):
        """Crop past key values to *new_cache_size* tokens."""
        if isinstance(past_key_values, DynamicCache):
            past_key_values.crop(new_cache_size)
            return past_key_values
        # Fallback for tuple-based caches
        if isinstance(past_key_values, (list, tuple)):
            new_past = []
            for layer_past in past_key_values:
                new_past.append(
                    tuple(t[..., :new_cache_size, :] for t in layer_past)
                )
            return type(past_key_values)(new_past)
        # If the cache has a crop method, use it
        if hasattr(past_key_values, "crop"):
            past_key_values.crop(new_cache_size)
            return past_key_values
        return past_key_values

    cg._crop_past_key_values = _crop_past_key_values  # type: ignore[attr-defined]
    logger.debug("Patched _crop_past_key_values")


# ---------------------------------------------------------------------------
# 4.  SequenceSummary  (removed from modeling_utils in 4.57, now per-model)
# ---------------------------------------------------------------------------
def _patch_sequence_summary() -> None:
    import transformers.modeling_utils as mu

    if hasattr(mu, "SequenceSummary"):
        return

    # GPT2SequenceSummary is functionally identical to the old generic one.
    from transformers.models.gpt2.modeling_gpt2 import GPT2SequenceSummary

    mu.SequenceSummary = GPT2SequenceSummary  # type: ignore[attr-defined]
    logger.debug("Patched transformers.modeling_utils.SequenceSummary")
