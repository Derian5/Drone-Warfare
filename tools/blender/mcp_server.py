"""Small local MCP stdio adapter for the official Blender MCP addon.

Standard-library-only: initialize -> tools/list -> tools/call, JSON-RPC 2.0.
The official addon executes bpy operations on the open Blender's main thread.
No headless Blender process, remote services or generated assets are involved.
"""

import json
import os
import socket
import sys

TOOLS = [
    {"name": "get_scene_info", "description": "Inspect the open local Blender scene.", "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "execute_blender_code", "description": "Execute Blender Python in the open Blender via its MCP addon.", "inputSchema": {"type": "object", "properties": {"code": {"type": "string"}}, "required": ["code"], "additionalProperties": False}},
]


def blender_command(kind, params):
    host = os.environ.get("BLENDER_HOST", "127.0.0.1")
    port = int(os.environ.get("BLENDER_PORT", "9876"))
    with socket.create_connection((host, port), timeout=5) as connection:
        connection.settimeout(240)
        connection.sendall(json.dumps({"type": kind, "params": params}).encode("utf-8"))
        data = bytearray()
        while True:
            part = connection.recv(65536)
            if not part:
                raise RuntimeError("Blender closed the connection before returning a complete response")
            data.extend(part)
            if len(data) > 8 * 1024 * 1024:
                raise RuntimeError("Blender response exceeds 8 MiB")
            try:
                return json.loads(data)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue


def handle(request):
    method = request.get("method")
    params = request.get("params", {})
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", "2024-11-05"), "capabilities": {"tools": {"listChanged": False}}, "serverInfo": {"name": "drone-warfare-local-blender", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        name = params.get("name")
        arguments = params.get("arguments", {})
        try:
            if name == "get_scene_info":
                result = blender_command("get_scene_info", {})
            elif name == "execute_blender_code":
                result = blender_command("execute_code", {"code": arguments["code"]})
            else:
                raise ValueError(f"Unknown tool: {name}")
            return {"content": [{"type": "text", "text": json.dumps(result, ensure_ascii=False)}], "isError": result.get("status") != "success"}
        except Exception as error:
            return {"content": [{"type": "text", "text": str(error)}], "isError": True}
    raise ValueError(f"Unsupported method: {method}")


def main():
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:  # notifications/initialized and cancellation
            continue
        response = {"jsonrpc": "2.0", "id": request["id"]}
        try:
            response["result"] = handle(request)
        except Exception as error:
            response["error"] = {"code": -32603, "message": str(error)}
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
