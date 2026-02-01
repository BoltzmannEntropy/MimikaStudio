"""Claude Code CLI provider.

Wraps the local 'claude' CLI (installed via @anthropic-ai/claude-code) and
invokes it in non-interactive print mode to get a single response.

Notes:
- We pass --print and --output-format text to capture plain text.
- We disable persistence with --no-session-persistence to keep runs stateless.
- We disable tools by default (--tools "") to avoid shell edits etc.
"""
import os
import subprocess
import shutil
from typing import Optional
from .base import LLMProvider


class ClaudeCodeCLIProvider(LLMProvider):
    """Claude Code CLI provider - uses local claude command."""

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        super().__init__(model, api_key, api_base)
        self.claude_path = shutil.which("claude")
        if not self.claude_path:
            raise RuntimeError("Claude CLI not found in PATH. Install @anthropic-ai/claude-code.")

        # Use model from env if not specified
        if not self.model:
            self.model = os.environ.get('LLM_MODEL', '')

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        # Build command arguments
        cmd = [
            self.claude_path,
            "--print",
            "--output-format", "text",
            "--no-session-persistence",  # Keep runs stateless
        ]

        # Disable tools by default to avoid shell edits
        enable_tools = os.environ.get('CLAUDE_ENABLE_TOOLS') == '1' or os.environ.get('LLM_ENABLE_TOOLS') == '1'
        if not enable_tools:
            cmd.extend(["--tools", ""])

        # Add model if specified
        if self.model:
            cmd.extend(["--model", self.model])

        # Build the full prompt with system prompt if provided
        full_prompt = prompt
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{prompt}"

        # Append prompt as the final argument (not with -p flag)
        cmd.append(full_prompt)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
        except subprocess.TimeoutExpired:
            raise RuntimeError("Claude CLI timed out")

        if result.returncode != 0:
            raise RuntimeError(f"Claude CLI failed: {result.stderr}")

        output = result.stdout.strip()
        if not output:
            raise RuntimeError("Claude CLI returned empty output")

        return output

    def get_name(self) -> str:
        return "claude_code_cli"
