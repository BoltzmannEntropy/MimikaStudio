"""LLM Provider Factory."""
import os
import json
import shutil
from pathlib import Path
from typing import Optional, Dict, Any

from .base import LLMProvider
from .claude_provider import ClaudeProvider
from .openai_provider import OpenAIProvider, OllamaProvider
from .claude_cli_provider import ClaudeCodeCLIProvider
from .codex_provider import CodexProvider


# Config file path
CONFIG_PATH = Path(__file__).parent.parent / "data" / "llm_config.json"


def get_available_providers() -> list:
    """Get list of available providers."""
    providers = ["claude", "openai", "ollama", "codex"]

    # Check if Claude CLI is available
    if shutil.which("claude"):
        providers.append("claude_code_cli")

    return providers


def load_config() -> Dict[str, Any]:
    """Load LLM configuration from file."""
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            return json.load(f)
    return {
        "provider": "claude",
        "model": "claude-sonnet-4-20250514",
        "api_key": None,
        "api_base": None
    }


def save_config(config: Dict[str, Any]) -> None:
    """Save LLM configuration to file."""
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)


def get_llm_provider(
    provider: Optional[str] = None,
    model: Optional[str] = None,
    api_key: Optional[str] = None,
    api_base: Optional[str] = None
) -> LLMProvider:
    """Get an LLM provider instance.

    Priority:
    1. Function arguments
    2. Config file
    3. Environment variables
    4. Auto-detection
    """
    # Load config
    config = load_config()

    # Resolve provider
    provider = provider or config.get("provider") or os.environ.get("LLM_PROVIDER")

    # Auto-detect if not specified
    if not provider:
        if shutil.which("claude") and not os.environ.get("ANTHROPIC_API_KEY"):
            provider = "claude_code_cli"
        elif os.environ.get("ANTHROPIC_API_KEY"):
            provider = "claude"
        elif os.environ.get("OPENAI_API_KEY"):
            provider = "openai"
        elif os.environ.get("OLLAMA_API_BASE"):
            provider = "ollama"
        else:
            provider = "claude"  # Default

    # Resolve other params from config
    model = model or config.get("model")
    api_key = api_key or config.get("api_key")
    api_base = api_base or config.get("api_base")

    # Create provider instance
    if provider == "claude":
        return ClaudeProvider(model=model, api_key=api_key, api_base=api_base)
    elif provider == "openai":
        return OpenAIProvider(model=model, api_key=api_key, api_base=api_base)
    elif provider == "ollama":
        return OllamaProvider(model=model, api_key=api_key, api_base=api_base)
    elif provider == "claude_code_cli":
        return ClaudeCodeCLIProvider(model=model)
    elif provider == "codex":
        return CodexProvider(model=model, api_key=api_key, api_base=api_base)
    else:
        raise ValueError(f"Unknown provider: {provider}")
