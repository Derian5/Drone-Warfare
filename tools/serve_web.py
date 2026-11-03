"""Local HTTP server for the exported game. No extra Python packages needed."""

import argparse
import functools
import http.server
import pathlib
import threading
import webbrowser


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="Open the game in the default browser")
    parser.add_argument("--directory", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1] / "build" / "web")
    args = parser.parse_args()
    if not (args.directory / "index.html").is_file():
        parser.error(f"No exported index.html in {args.directory}")
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(args.directory))
    url = f"http://127.0.0.1:{args.port}/"
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Drone Warfare: {url}\nKeep this window open. Ctrl+C stops the server.", flush=True)
        if args.open:
            threading.Timer(0.5, lambda: webbrowser.open(url)).start()
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
