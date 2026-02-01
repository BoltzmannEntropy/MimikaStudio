"""Codex provider using MCP HTTP JSON-RPC protocol."""
import os
import json
import urllib.request
from typing import Optional
from .base import LLMProvider


class CodexProvider(LLMProvider):
    """Provider for Codex via MCP HTTP server."""

    def __init__(self, model: Optional[str] = None, api_key: Optional[str] = None,
                 api_base: Optional[str] = None):
        super().__init__(model, api_key, api_base)
        # Get URL from api_base or environment
        self.base_url = api_base or os.environ.get('LLM_MCP_URL') or os.environ.get('CODEX_MCP_URL', '')
        self.tool_name = os.environ.get('LLM_MCP_TOOL') or os.environ.get('CODEX_MCP_TOOL', 'ask')
        self.timeout = int(os.environ.get('LLM_TIMEOUT', '180'))

        if not self.base_url:
            raise ValueError("Codex provider requires MCP URL. Set LLM_MCP_URL or CODEX_MCP_URL environment variable.")

    def _http_jsonrpc(self, method: str, params: Optional[dict] = None) -> dict:
        """Make HTTP JSON-RPC call."""
        payload = json.dumps({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params or {}
        }).encode('utf-8')

        req = urllib.request.Request(
            self.base_url,
            data=payload,
            headers={"Content-Type": "application/json"}
        )

        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            body = resp.read().decode('utf-8')

        obj = json.loads(body)
        if 'error' in obj:
            raise RuntimeError(f"RPC error: {obj['error']}")
        return obj.get('result', {})

    def _pick_tool(self, tools: list, prefer: Optional[str] = None) -> str:
        """Pick best tool from available tools."""
        names = [t.get('name') for t in tools if t.get('name')]
        if prefer and prefer in names:
            return prefer
        # Try common generation tool names
        for candidate in ('ask', 'generate', 'completion', 'complete'):
            for name in names:
                if candidate in name.lower():
                    return name
        if names:
            return names[0]
        raise RuntimeError('No tools available from Codex provider')

    def generate(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        """Generate text using Codex MCP server."""
        # Combine system prompt if provided
        full_prompt = prompt
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{prompt}"

        # List available tools
        result = self._http_jsonrpc('tools/list', {})
        tools = result.get('tools', [])
        tool_name = self._pick_tool(tools, self.tool_name)

        # Call the tool
        result = self._http_jsonrpc('tools/call', {
            "name": tool_name,
            "arguments": {"input": full_prompt}
        })

        # Extract text content
        pieces = []
        for content in result.get('content', []):
            if isinstance(content, dict) and content.get('type') == 'text':
                if 'text' in content:
                    pieces.append(content['text'])

        output = "\n".join(pieces).strip()
        if not output:
            raise RuntimeError("Empty response from Codex provider")
        return output

    def get_name(self) -> str:
        return "codex"
