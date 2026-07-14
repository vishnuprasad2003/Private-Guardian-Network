#!/usr/bin/env python3
"""Render systemd unit templates with host-specific user / path values."""
import os
import pathlib
import sys

def main() -> int:
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out_dir.mkdir(parents=True, exist_ok=True)
    replacements = {
        "__GUARDIAN_USER__": os.environ["GUARDIAN_USER"],
        "__GUARDIAN_GROUP__": os.environ["GUARDIAN_GROUP"],
        "__WORKSPACE_ROOT__": os.environ["WORKSPACE_ROOT"],
        "__HOME__": os.environ["HOME_DIR"],
    }
    root = pathlib.Path(__file__).resolve().parent.parent / "systemd"
    for name in ("anvil.service", "guardian@.service"):
        text = (root / name).read_text()
        for key, value in replacements.items():
            text = text.replace(key, value)
        (out_dir / name).write_text(text)
        print(f"rendered {name}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
