#!/usr/bin/env python3
"""Package standalone HTML apps and publish them to the MY APPS catalog."""

import base64
import hashlib
import json
import os
import re
import subprocess
import tempfile
import unicodedata
from html.parser import HTMLParser
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

CATALOG = Path("apps-catalog.json")
APPLICATIONS = Path("applications")
MAX_HTML_SIZE = 90 * 1024 * 1024


class PageTitle(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_title = False
        self.finished = False
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == "title" and not self.finished:
            self.in_title = True

    def handle_endtag(self, tag):
        if tag == "title" and self.in_title:
            self.in_title = False
            self.finished = True

    def handle_data(self, data):
        if self.in_title:
            self.parts.append(data)


def app_id(source):
    stem = unicodedata.normalize("NFKD", source.stem)
    stem = stem.encode("ascii", "ignore").decode("ascii").lower()
    slug = re.sub(r"[^a-z0-9]+", "-", stem).strip("-")
    if len(slug) > 48:
        slug = f"{slug[:37].rstrip('-')}-{sha256(slug.encode())[:10]}"
    if not slug or re.fullmatch(r"con|prn|aux|nul|com[0-9]|lpt[0-9]", slug):
        raise ValueError(f"Choisissez un autre nom pour {source.name}.")
    return slug


def app_name(html, slug):
    parser = PageTitle()
    parser.feed(html.decode("utf-8-sig", errors="replace"))
    name = " ".join("".join(parser.parts).split())
    if not name:
        return slug.replace("-", " ").capitalize()
    # The launcher uses .NET string length, which counts UTF-16 code units.
    return name.encode("utf-16-le")[:140].decode("utf-16-le", errors="ignore").rstrip()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def next_version(previous):
    if previous is None:
        return "1.0.0"
    value = previous["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", value, flags=re.ASCII):
        raise ValueError(f"Version de catalogue invalide : {value}.")
    major, minor, patch = (int(part) for part in value.split("."))
    if max(major, minor, patch + 1) > 2_147_483_647:
        raise ValueError(f"Version de catalogue hors limites : {value}.")
    return f"{major}.{minor}.{patch + 1}"


def write_pack(path, html, manifest):
    # Fixed entry timestamps make identical builds reusable after a failed run.
    with ZipFile(path, "w") as pack:
        for name, content in (("index.html", html), ("my-apps.json", json_bytes(manifest))):
            pack.writestr(ZipInfo(name), content, compress_type=ZIP_DEFLATED, compresslevel=9)


def build_catalog(catalog, sources, output):
    if catalog["schema"] != 1:
        raise ValueError("Le schéma du catalogue est incompatible.")
    entries = {entry["id"]: entry for entry in catalog["apps"]}
    if len(entries) != len(catalog["apps"]):
        raise ValueError("Le catalogue contient des identifiants en double.")

    packages = []
    seen = set()
    for source in sorted(sources):
        if source.suffix.lower() not in {".html", ".htm"}:
            continue
        if source.is_symlink() or not source.is_file() or source.stat().st_size > MAX_HTML_SIZE:
            raise ValueError(f"Le fichier {source.name} doit être un HTML autonome de 90 Mo au maximum.")
        slug = app_id(source)
        if slug in seen:
            raise ValueError(f"Plusieurs fichiers HTML utilisent l’identifiant {slug}.")
        seen.add(slug)
        previous = entries.get(slug)
        if previous and previous.get("source_file", source.name) != source.name:
            raise ValueError(f"{source.name} utilise le même identifiant que {previous['source_file']}.")
        html = source.read_bytes()
        if not html.strip():
            raise ValueError(f"Le fichier HTML {source.name} est vide.")
        source_hash = sha256(html)
        if previous and previous.get("source_sha256") == source_hash:
            continue

        version = next_version(previous)
        name = app_name(html, slug)
        manifest = {"schema": 1, "id": slug, "name": name, "version": version}
        path = output / f"{slug}-{version}.zip"
        write_pack(path, html, manifest)
        entry = {
            "id": slug,
            "name": name,
            "version": version,
            "asset": path.name,
            "sha256": sha256(path.read_bytes()),
            "source_file": source.name,
            "source_sha256": source_hash,
        }
        entries[slug] = entry
        packages.append((path, entry))

    if len(entries) > 250:
        raise ValueError("Le catalogue MY APPS est limité à 250 applications.")
    if not packages:
        return "", [], catalog

    package_hashes = "\n".join(entry["sha256"] for _, entry in packages)
    tag = f"catalogue-{sha256(package_hashes.encode())[:24]}"
    for _, entry in packages:
        entry["tag"] = tag
    return tag, packages, {**catalog, "apps": list(entries.values())}


def gh(*args, input_data=None):
    return subprocess.run(
        ["gh", *args],
        input=input_data,
        text=True,
        capture_output=True,
        check=True,
    )


def release_info(repo, tag):
    result = gh(
        "api", "--paginate", f"repos/{repo}/releases",
        "--jq", f'.[] | select(.tag_name == "{tag}") | {{id, draft}}',
    )
    return next((json.loads(line) for line in result.stdout.splitlines()), None)


def publish_release(repo, tag, packages, revision):
    release = release_info(repo, tag)
    if release is None:
        gh(
            "release", "create", tag, "--repo", repo, "--target", revision,
            "--draft", "--prerelease", "--latest=false",
            "--title", "Applications MY APPS",
            "--notes", "Packs publiés dans le catalogue du launcher MY APPS.",
        )
        release = release_info(repo, tag)
        if release is None:
            raise RuntimeError("GitHub ne renvoie pas la release créée.")

    if release["draft"]:
        gh("release", "upload", tag, *(str(path) for path, _ in packages), "--repo", repo, "--clobber")

    release_path = f"repos/{repo}/releases/{release['id']}"
    result = gh("api", "--paginate", f"{release_path}/assets", "--jq", ".[] | {name, digest, state}")
    uploaded = {asset["name"]: asset for asset in map(json.loads, result.stdout.splitlines())}
    for path, entry in packages:
        asset = uploaded.get(path.name)
        if not asset or asset["state"] != "uploaded" or asset["digest"] != f"sha256:{entry['sha256']}":
            raise RuntimeError(f"L’empreinte de {path.name} diffère sur GitHub.")

    if release["draft"]:
        gh("release", "edit", tag, "--repo", repo, "--draft=false", "--prerelease", "--latest=false")


def publish_catalog(repo, original, catalog):
    blob = b"blob " + str(len(original)).encode() + b"\0" + original
    request = {
        "branch": "main",
        "message": "Actualiser le catalogue des applications HTML",
        "sha": hashlib.sha1(blob).hexdigest(),
        "content": base64.b64encode(json_bytes(catalog)).decode("ascii"),
    }
    gh("api", "--method", "PUT", f"repos/{repo}/contents/{CATALOG}", "--input", "-", input_data=json.dumps(request))


def main():
    original = CATALOG.read_bytes()
    with tempfile.TemporaryDirectory(prefix="my-apps-") as temporary:
        tag, packages, catalog = build_catalog(json.loads(original), APPLICATIONS.iterdir(), Path(temporary))
        if not packages:
            print("Le catalogue est déjà à jour.")
            return
        repo = os.environ["GITHUB_REPOSITORY"]
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
        publish_release(repo, tag, packages, revision)
        publish_catalog(repo, original, catalog)
        for _, entry in packages:
            print(f"Publié : {entry['name']} v{entry['version']}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        raise SystemExit(detail) from error
