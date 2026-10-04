"""Paths and JSON/CSV helpers. Everything the CLI writes lives in workspace/ (gitignored)."""
import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("ELIAS_ROOT", Path(__file__).resolve().parent.parent))
CONFIG = ROOT / "config"
DATA = ROOT / "data"
WORKSPACE = Path(os.environ.get("ELIAS_WORKSPACE", ROOT / "workspace"))
ASSETS = ROOT / "assets"


def load(path, default=None):
    path = Path(path)
    if not path.exists():
        if default is not None:
            return default
        raise FileNotFoundError(path)
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def save(path, obj):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")
    tmp.replace(path)


def character():
    return load(CONFIG / "character.json")


def styles():
    return load(CONFIG / "styles.json")


def settings():
    path = WORKSPACE / "settings.json"
    if path.exists():
        return load(path)
    return load(CONFIG / "settings.example.json")
