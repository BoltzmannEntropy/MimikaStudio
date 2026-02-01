"""OpenAI-compatible provider (OpenAI, Ollama, llama.cpp)."""
import os
import httpx
from typing import Optional
from .base import LLMProvider


class OpenAIProvider(LLMProvider):
    """OpenAI-compatible API provider."""

    DEFAULT_MODEL = "gpt-4"
    DEFAULT_API_BASE = "https://api.openai.com/v1/chat/completions"

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        super().__init__(model, api_key, api_base)
        self.model = model or self.DEFAULT_MODEL
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        self.api_base = api_base or os.environ.get("OPENAI_API_BASE", self.DEFAULT_API_BASE)

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        headers = {
            "Content-Type": "application/json",
        }

        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        data = {
            "model": self.model,
            "messages": messages,
            "max_tokens": 4096,
            "temperature": 0.7
        }

        with httpx.Client(timeout=180) as client:
            response = client.post(self.api_base, headers=headers, json=data)
            response.raise_for_status()
            result = response.json()
            return result["choices"][0]["message"]["content"]

    def get_name(self) -> str:
        return "openai"


class OllamaProvider(OpenAIProvider):
    """Ollama provider (OpenAI-compatible API)."""

    DEFAULT_MODEL = "llama3.2"
    DEFAULT_API_BASE = "http://localhost:11434/v1/chat/completions"

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        super().__init__(model, api_key, api_base)
        self.model = model or self.DEFAULT_MODEL
        self.api_base = api_base or os.environ.get("OLLAMA_API_BASE", self.DEFAULT_API_BASE)
        self.api_key = api_key or "ollama"  # Ollama doesn't require a real key

    def get_name(self) -> str:
        return "ollama"
