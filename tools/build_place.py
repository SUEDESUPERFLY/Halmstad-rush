#!/usr/bin/env python3
"""Bygger build/HalmstadRush.rbxlx från default.project.json utan att Rojo behövs.

Följer Rojos namnregler för det projektet använder:
  mapp med init.server.luau -> Script, init.client.luau -> LocalScript, init.luau -> ModuleScript
  annars mapp -> Folder
  X.server.luau -> Script, X.client.luau -> LocalScript, X.luau -> ModuleScript

Användning: python3 tools/build_place.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "build" / "HalmstadRush.rbxlx"

_referent = 0


def next_ref() -> str:
    global _referent
    _referent += 1
    return f"RBX{_referent:08X}"


def cdata(text: str) -> str:
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(class_name: str, name: str, children: list[str], source: str | None = None) -> str:
    props = [f'<string name="Name">{escape(name)}</string>']
    if source is not None:
        props.append(f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>')
    inner = "".join(children)
    return (
        f'<Item class="{class_name}" referent="{next_ref()}">'
        f"<Properties>{''.join(props)}</Properties>{inner}</Item>"
    )


SCRIPT_SUFFIXES = [
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".luau", "ModuleScript"),
]


def classify_file(path: Path) -> tuple[str, str] | None:
    for suffix, class_name in SCRIPT_SUFFIXES:
        if path.name.endswith(suffix):
            return class_name, path.name[: -len(suffix)]
    return None


def build_path(path: Path, name: str) -> str:
    if path.is_file():
        kind = classify_file(path)
        if kind is None:
            raise SystemExit(f"Okänd filtyp: {path}")
        return item(kind[0], name, [], path.read_text(encoding="utf-8"))

    init_class, init_source = "Folder", None
    for init_name, class_name in [
        ("init.server.luau", "Script"),
        ("init.client.luau", "LocalScript"),
        ("init.luau", "ModuleScript"),
    ]:
        init_file = path / init_name
        if init_file.exists():
            init_class, init_source = class_name, init_file.read_text(encoding="utf-8")
            break

    children = []
    for child in sorted(path.iterdir()):
        if child.name.startswith("init.") or child.name.startswith("."):
            continue
        if child.is_dir():
            children.append(build_path(child, child.name))
        else:
            kind = classify_file(child)
            if kind is not None:
                children.append(build_path(child, kind[1]))
    return item(init_class, name, children, init_source)


def build_node(name: str, node: dict, is_service: bool) -> str:
    if "$path" in node:
        return build_path(ROOT / node["$path"], name)
    class_name = node.get("$className", name if is_service else "Folder")
    children = [
        build_node(child_name, child, False)
        for child_name, child in node.items()
        if not child_name.startswith("$")
    ]
    return item(class_name, name, children)


def main() -> None:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    tree = project["tree"]
    services = [
        build_node(name, node, True) for name, node in tree.items() if not name.startswith("$")
    ]
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        + "".join(services)
        + "</roblox>\n"
    )
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text(xml, encoding="utf-8")
    print(f"Byggde {OUTPUT.relative_to(ROOT)} ({len(xml)} byte)")


if __name__ == "__main__":
    sys.exit(main())
