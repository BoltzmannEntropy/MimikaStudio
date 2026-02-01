"""Claude API provider."""
import os
import httpx
from typing import Optional
from .base import LLMProvider


class ClaudeProvider(LLMProvider):
    """Claude API provider using Anthropic's API."""

    DEFAULT_MODEL = "claude-sonnet-4-20250514"
    API_URL = "https://api.anthropic.com/v1/messages"

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        super().__init__(model, api_key, api_base)
        self.model = model or self.DEFAULT_MODEL
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY")
        self.api_base = api_base or self.API_URL

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY not set")

        headers = {
            "Content-Type": "application/json",
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01"
        }

        data = {
            "model": self.model,
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": prompt}]
        }

        if system_prompt:
            data["system"] = system_prompt

        with httpx.Client(timeout=180) as client:
            response = client.post(self.api_base, headers=headers, json=data)
            response.raise_for_status()
            result = response.json()
            return result["content"][0]["text"]

    def get_name(self) -> str:
        return "claude"
