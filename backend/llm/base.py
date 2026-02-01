"""Base LLM Provider interface."""
from abc import ABC, abstractmethod
from typing import Optional


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        self.model = model
        self.api_key = api_key
        self.api_base = api_base

    @abstractmethod
    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """Generate text from a prompt."""
        pass

    @abstractmethod
    def get_name(self) -> str:
        """Get the provider name."""
        pass
