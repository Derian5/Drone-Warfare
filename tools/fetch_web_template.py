"""Fetch only the single-threaded Web template, not the 1.2 GB platform bundle.

Python standard library only. --list transfers the ZIP directory, not templates.
Downloading a template requires the explicit --download flag.
"""

import argparse
import io
import pathlib
import urllib.request
import zipfile


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=40) as response:
            self.url = response.url
            self.length = int(response.headers["Content-Length"])
        self.position = 0
        self.transferred = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        self.position = offset + (self.length if whence == io.SEEK_END else self.position if whence == io.SEEK_CUR else 0)
        return self.position

    def read(self, size=-1):
        if size < 0:
            size = self.length - self.position
        size = min(size, self.length - self.position)
        if size <= 0:
            return b""
        if size > 64 * 1024 * 1024:
            raise ValueError("Refusing a request larger than 64 MiB")
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.position}-{self.position + size - 1}"})
        with urllib.request.urlopen(request, timeout=90) as response:
            if response.status != 206:
                raise RuntimeError("Server ignored Range; refusing full bundle download")
            data = response.read(size)
        self.position += len(data)
        self.transferred += len(data)
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="4.7.2")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    args = parser.parse_args()
    url = f"https://github.com/godotengine/godot-builds/releases/download/{args.version}-stable/Godot_v{args.version}-stable_export_templates.tpz"
    source = RemoteZip(url)
    with zipfile.ZipFile(source) as bundle:
        for entry in bundle.infolist():
            if "web" in entry.filename.lower():
                print(f"{entry.filename}: download {entry.compress_size / 1048576:.2f} MiB, extracted {entry.file_size / 1048576:.2f} MiB")
        if args.download:
            if args.output is None or not args.output.parent.is_dir():
                parser.error("--output must name a file in an existing directory")
            if args.output.exists():
                parser.error("Output already exists; refusing to overwrite")
            matches = [item for item in bundle.infolist() if item.filename.endswith("/web_nothreads_release.zip")]
            if len(matches) != 1:
                raise RuntimeError("Expected exactly one web_nothreads_release.zip")
            data = bundle.read(matches[0])  # ZipFile verifies the member CRC.
            with zipfile.ZipFile(io.BytesIO(data)) as template:
                if template.testzip() is not None:
                    raise RuntimeError("Invalid nested Web template")
            args.output.write_bytes(data)
            print(f"Saved: {args.output}")
    print(f"Transferred: {source.transferred / 1048576:.2f} MiB")


if __name__ == "__main__":
    main()
