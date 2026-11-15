"""Build the Windows package and the backward-compatible launcher update."""
import json
from pathlib import Path
import re
import sys
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r"(?m)^\$baseVersion = \[version\]'((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))'$"
UPDATE_FILES = ("MY_APPS_App.ps1", "MY_APPS.xaml")
WINDOWS_FILES = (*UPDATE_FILES, "MY_APPS.cmd", "MY_APPS.ps1", "LIRE_EN_PREMIER.txt", "Demo_Mes_Notes.zip")


def build(output: Path) -> str:
    bootstrap = (ROOT / "MY_APPS.ps1").read_text(encoding="utf-8-sig")
    versions = re.findall(VERSION_PATTERN, bootstrap)
    if len(versions) != 1:
        raise ValueError("Impossible de déterminer la version du launcher.")
    version = versions[0]
    output.mkdir(parents=True, exist_ok=True)

    with ZipFile(output / f"MY_APPS_Mise_a_jour_v{version}.zip", "w", ZIP_DEFLATED) as update:
        manifest = {"schema": 1, "product": "MY_APPS_LAUNCHER", "version": version}
        update.writestr("my-apps-update.json", json.dumps(manifest) + "\n")
        for name in UPDATE_FILES:
            update.write(ROOT / name, name)

    with ZipFile(output / f"MY_APPS_Windows_v{version}.zip", "w", ZIP_DEFLATED) as package:
        for name in WINDOWS_FILES:
            package.write(ROOT / name, name)

    return version


if __name__ == "__main__":
    print(build(Path(sys.argv[1])))
