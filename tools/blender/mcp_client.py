"""One-shot MCP client for this session; also useful for reproducible bpy scripts."""

import argparse
import json
import pathlib
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", type=pathlib.Path)
    args = parser.parse_args()
    server = pathlib.Path(__file__).with_name("mcp_server.py")
    process = subprocess.Popen([sys.executable, str(server)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")

    def send(payload):
        process.stdin.write(json.dumps(payload) + "\n")
        process.stdin.flush()

    def rpc(id, method, params):
        send({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
        response = json.loads(process.stdout.readline())
        if "error" in response:
            raise RuntimeError(response["error"])
        return response["result"]

    try:
        initialized = rpc(1, "initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "drone-warfare-pipeline", "version": "1.0"}})
        print(f"MCP connected: {initialized['serverInfo']['name']}")
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        listed = rpc(2, "tools/list", {})
        print("MCP tools: " + ", ".join(item["name"] for item in listed["tools"]))
        name = "execute_blender_code" if args.script else "get_scene_info"
        arguments = {"code": args.script.read_text(encoding="utf-8")} if args.script else {}
        result = rpc(3, "tools/call", {"name": name, "arguments": arguments})
        for content in result.get("content", []):
            if content["type"] == "text":
                print(content["text"])
        if result.get("isError"):
            raise SystemExit(1)
    finally:
        process.stdin.close()
        process.wait(timeout=5)


if __name__ == "__main__":
    main()
