"""Tests for the MimikaStudio MCP Server (bin/tts_mcp_server.py).

Tests tool definitions, schema validation, tool call dispatch, and the
JSON-RPC HTTP handler -- all without starting a live server or requiring
the backend to be running.
"""

import json
import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# The MCP server lives outside the backend package tree.  Add its directory
# so we can import it as a regular module.
MCP_SERVER_PATH = Path(__file__).resolve().parents[2] / "bin" / "tts_mcp_server.py"
BIN_DIR = str(MCP_SERVER_PATH.parent)

if BIN_DIR not in sys.path:
    sys.path.insert(0, BIN_DIR)


# We need to handle the fact that importing the module triggers _setup_logging
# and potentially creates log directories.  Patch minimally.
@pytest.fixture(scope="module")
def mcp_module():
    """Import the MCP server module."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("tts_mcp_server", str(MCP_SERVER_PATH))
    mod = importlib.util.module_from_spec(spec)
    # Patch the logging setup so it does not write files during tests
    with patch.dict("os.environ", {"LOG_LEVEL": "CRITICAL"}):
        spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------

class TestMCPToolDefinitions:
    """Validate MCP_TOOLS list and individual tool schemas."""

    def test_mcp_tools_is_list(self, mcp_module):
        assert isinstance(mcp_module.MCP_TOOLS, list)

    def test_mcp_tools_not_empty(self, mcp_module):
        assert len(mcp_module.MCP_TOOLS) > 0

    def test_each_tool_has_required_keys(self, mcp_module):
        for tool in mcp_module.MCP_TOOLS:
            assert "name" in tool, f"Tool missing 'name': {tool}"
            assert "description" in tool, f"Tool missing 'description': {tool}"
            assert "inputSchema" in tool, f"Tool missing 'inputSchema': {tool}"

    def test_tool_names_are_unique(self, mcp_module):
        names = [t["name"] for t in mcp_module.MCP_TOOLS]
        assert len(names) == len(set(names)), f"Duplicate tool names: {names}"

    def test_tool_input_schemas_are_objects(self, mcp_module):
        for tool in mcp_module.MCP_TOOLS:
            schema = tool["inputSchema"]
            assert schema.get("type") == "object", (
                f"Tool '{tool['name']}' inputSchema type should be 'object'"
            )

    def test_expected_tools_present(self, mcp_module):
        names = {t["name"] for t in mcp_module.MCP_TOOLS}
        expected = {
            "tts_generate_kokoro",
            "tts_generate_qwen3",
            "tts_list_voices",
            "tts_system_info",
            "tts_system_stats",
        }
        assert expected.issubset(names), f"Missing tools: {expected - names}"

    def test_kokoro_tool_requires_text(self, mcp_module):
        tool = next(t for t in mcp_module.MCP_TOOLS if t["name"] == "tts_generate_kokoro")
        assert "required" in tool["inputSchema"]
        assert "text" in tool["inputSchema"]["required"]

    def test_qwen3_tool_requires_text_and_voice(self, mcp_module):
        tool = next(t for t in mcp_module.MCP_TOOLS if t["name"] == "tts_generate_qwen3")
        required = tool["inputSchema"]["required"]
        assert "text" in required
        assert "voice_name" in required

    def test_list_voices_tool_requires_engine(self, mcp_module):
        tool = next(t for t in mcp_module.MCP_TOOLS if t["name"] == "tts_list_voices")
        assert "required" in tool["inputSchema"]
        assert "engine" in tool["inputSchema"]["required"]

    def test_system_info_tool_no_required_args(self, mcp_module):
        tool = next(t for t in mcp_module.MCP_TOOLS if t["name"] == "tts_system_info")
        schema = tool["inputSchema"]
        # Either no 'required' key or empty list
        required = schema.get("required", [])
        assert len(required) == 0

    def test_tool_descriptions_are_nonempty(self, mcp_module):
        for tool in mcp_module.MCP_TOOLS:
            assert len(tool["description"].strip()) > 0, (
                f"Tool '{tool['name']}' has empty description"
            )


# ---------------------------------------------------------------------------
# Tool call handler
# ---------------------------------------------------------------------------

class TestHandleToolCall:
    """Test handle_tool_call dispatches correctly (with mocked backend)."""

    def test_unknown_tool_returns_message(self, mcp_module):
        result = mcp_module.handle_tool_call("nonexistent_tool", {})
        assert "Unknown tool" in result

    @patch.object(sys.modules.get("tts_mcp_server", MagicMock()), "_call_backend", create=True)
    def test_kokoro_generate_calls_backend(self, mock_call, mcp_module):
        """Verify tts_generate_kokoro calls the right backend endpoint."""
        with patch.object(mcp_module, "_call_backend", return_value={
            "audio_url": "/audio/kokoro-test.wav",
            "filename": "kokoro-test.wav",
        }) as mock_be:
            result = mcp_module.handle_tool_call("tts_generate_kokoro", {
                "text": "Hello",
                "voice": "bf_emma",
            })
            mock_be.assert_called_once()
            call_args = mock_be.call_args
            assert "/api/kokoro/generate" in call_args[0][0]
            assert "Audio generated" in result

    def test_qwen3_generate_calls_backend(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "audio_url": "/audio/qwen3-test.wav",
            "filename": "qwen3-test.wav",
        }) as mock_be:
            result = mcp_module.handle_tool_call("tts_generate_qwen3", {
                "text": "Hello",
                "voice_name": "Natasha",
            })
            mock_be.assert_called_once()
            assert "/api/qwen3/generate" in mock_be.call_args[0][0]
            assert "Audio generated" in result

    def test_list_voices_kokoro(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "voices": [
                {"code": "bf_emma", "name": "Emma"},
                {"code": "bm_george", "name": "George"},
            ],
        }):
            result = mcp_module.handle_tool_call("tts_list_voices", {"engine": "kokoro"})
            assert "Kokoro voices" in result
            assert "bf_emma" in result

    def test_list_voices_qwen3(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "voices": [
                {"name": "Natasha", "source": "sample"},
            ],
        }):
            result = mcp_module.handle_tool_call("tts_list_voices", {"engine": "qwen3"})
            assert "Qwen3 voices" in result
            assert "Natasha" in result

    def test_list_voices_unknown_engine(self, mcp_module):
        result = mcp_module.handle_tool_call("tts_list_voices", {"engine": "unknown"})
        assert "Unknown engine" in result

    def test_system_info(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "python_version": "3.11.0",
            "device": "CPU",
        }):
            result = mcp_module.handle_tool_call("tts_system_info", {})
            assert "python_version" in result

    def test_system_stats(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "cpu_percent": 25.0,
            "ram_used_gb": 8.0,
            "ram_total_gb": 16.0,
            "gpu": None,
        }):
            result = mcp_module.handle_tool_call("tts_system_stats", {})
            assert "CPU" in result
            assert "RAM" in result

    def test_system_stats_with_gpu(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", return_value={
            "cpu_percent": 10.0,
            "ram_used_gb": 4.0,
            "ram_total_gb": 32.0,
            "gpu": {
                "name": "NVIDIA RTX 4090",
                "memory_used_gb": 2.5,
                "memory_total_gb": 24.0,
            },
        }):
            result = mcp_module.handle_tool_call("tts_system_stats", {})
            assert "NVIDIA RTX 4090" in result

    def test_tool_error_returns_error_message(self, mcp_module):
        with patch.object(mcp_module, "_call_backend", side_effect=Exception("backend down")):
            result = mcp_module.handle_tool_call("tts_system_info", {})
            assert "Error" in result


# ---------------------------------------------------------------------------
# Server constants and metadata
# ---------------------------------------------------------------------------

class TestServerMetadata:
    """Check server name, version, and constants."""

    def test_server_name(self, mcp_module):
        assert mcp_module.SERVER_NAME == "mimikastudio-mcp"

    def test_server_version(self, mcp_module):
        # Should be a valid semver-like string (e.g. "1.0.0", "2.0.0")
        parts = mcp_module.SERVER_VERSION.split(".")
        assert len(parts) == 3, f"Expected semver format, got: {mcp_module.SERVER_VERSION}"
        for part in parts:
            assert part.isdigit(), f"Non-numeric version part: {part}"

    def test_backend_url_default(self, mcp_module):
        # When env var is not set, defaults to localhost
        assert "localhost" in mcp_module.BACKEND_URL or "127.0.0.1" in mcp_module.BACKEND_URL


# ---------------------------------------------------------------------------
# JSON-RPC protocol (unit-test the handler logic without HTTP)
# ---------------------------------------------------------------------------

class TestMCPHandlerProtocol:
    """Test MCPHandler JSON-RPC protocol by simulating requests."""

    def _make_request(self, mcp_module, body_dict: dict) -> dict:
        """Simulate a POST request to MCPHandler and return the response dict."""
        body_bytes = json.dumps(body_dict).encode("utf-8")

        # Create a mock request handler without actually starting a server
        handler = mcp_module.MCPHandler.__new__(mcp_module.MCPHandler)
        handler.headers = {"Content-Length": str(len(body_bytes))}
        handler.rfile = BytesIO(body_bytes)

        response_buf = BytesIO()
        handler.wfile = response_buf

        # Mock send_response, send_header, end_headers
        handler.send_response = MagicMock()
        handler.send_header = MagicMock()
        handler.end_headers = MagicMock()

        handler.do_POST()

        response_buf.seek(0)
        return json.loads(response_buf.read().decode("utf-8"))

    def test_initialize_returns_server_info(self, mcp_module):
        resp = self._make_request(mcp_module, {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": "2024-11-05"},
        })
        assert resp["id"] == 1
        assert "result" in resp
        result = resp["result"]
        assert result["serverInfo"]["name"] == "mimikastudio-mcp"
        assert "capabilities" in result

    def test_tools_list_returns_tools(self, mcp_module):
        resp = self._make_request(mcp_module, {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
        })
        assert resp["id"] == 2
        assert "tools" in resp["result"]
        assert len(resp["result"]["tools"]) > 0

    def test_tools_list_alternate_method(self, mcp_module):
        """tools.list should also work (dot notation)."""
        resp = self._make_request(mcp_module, {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools.list",
        })
        assert "tools" in resp["result"]

    def test_tools_call_dispatches(self, mcp_module):
        with patch.object(mcp_module, "handle_tool_call", return_value="test result") as mock_htc:
            resp = self._make_request(mcp_module, {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {
                    "name": "tts_system_info",
                    "arguments": {},
                },
            })
            mock_htc.assert_called_once_with("tts_system_info", {})
            assert resp["id"] == 4
            content = resp["result"]["content"]
            assert content[0]["type"] == "text"
            assert content[0]["text"] == "test result"

    def test_unknown_method_returns_error(self, mcp_module):
        resp = self._make_request(mcp_module, {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "unknown/method",
        })
        assert "error" in resp
        assert resp["error"]["code"] == -32601

    def test_invalid_json_returns_parse_error(self, mcp_module):
        """Test with malformed JSON."""
        handler = mcp_module.MCPHandler.__new__(mcp_module.MCPHandler)
        bad_body = b"not json at all {"
        handler.headers = {"Content-Length": str(len(bad_body))}
        handler.rfile = BytesIO(bad_body)

        response_buf = BytesIO()
        handler.wfile = response_buf
        handler.send_response = MagicMock()
        handler.send_header = MagicMock()
        handler.end_headers = MagicMock()

        handler.do_POST()

        response_buf.seek(0)
        resp = json.loads(response_buf.read().decode("utf-8"))
        assert "error" in resp
        assert resp["error"]["code"] == -32700

    def test_initialize_preserves_protocol_version(self, mcp_module):
        resp = self._make_request(mcp_module, {
            "jsonrpc": "2.0",
            "id": 6,
            "method": "initialize",
            "params": {"protocolVersion": "2025-01-01"},
        })
        assert resp["result"]["protocolVersion"] == "2025-01-01"

    def test_tools_call_with_arguments(self, mcp_module):
        with patch.object(mcp_module, "handle_tool_call", return_value="voices listed") as mock_htc:
            resp = self._make_request(mcp_module, {
                "jsonrpc": "2.0",
                "id": 7,
                "method": "tools/call",
                "params": {
                    "name": "tts_list_voices",
                    "arguments": {"engine": "kokoro"},
                },
            })
            mock_htc.assert_called_once_with("tts_list_voices", {"engine": "kokoro"})
