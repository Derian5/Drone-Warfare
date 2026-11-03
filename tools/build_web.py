"""Build and package the single-threaded Godot 4.7.2 browser prototype."""

import argparse
import pathlib
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_GODOT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--download-template", action="store_true", help="Download only the ~10 MiB Web release template if missing")
    parser.add_argument("--package-only", action="store_true", help="Package an already exported build")
    args = parser.parse_args()
    output = ROOT / "build" / "web"
    template = ROOT / ".godot" / "web_templates" / "web_nothreads_release.zip"
    if not args.package_only:
        if not template.is_file():
            if not args.download_template:
                parser.error("Web template missing. Use --download-template or install it in .godot/web_templates/.")
            template.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([sys.executable, str(ROOT / "tools" / "fetch_web_template.py"), "--download", "--output", str(template)], check=True)
        output.mkdir(parents=True, exist_ok=True)
        subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(output / "index.html")], cwd=ROOT, check=True)
    for name in ["index.html", "index.js", "index.wasm", "index.pck"]:
        if not (output / name).is_file():
            parser.error(f"Missing build file: {name}")
    archive = ROOT / "build" / "Drone-Warfare-Web.zip"
    files = [item for item in output.iterdir() if item.is_file() and not item.name.startswith(".")]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for item in sorted(files):
            bundle.write(item, item.name)
    print(f"Web build: {output}")
    print(f"Files: {len(files)}, unpacked: {sum(item.stat().st_size for item in files) / 1048576:.2f} MiB")
    print(f"Archive: {archive} ({archive.stat().st_size / 1048576:.2f} MiB)")


if __name__ == "__main__":
    main()
