"""Consistent verse text for the public reader and administrator editor."""
from __future__ import annotations

from typing import Any


def extract_verse_text(data: Any) -> str:
    if not isinstance(data, dict):
        return ""
    text = str(data.get("text") or "").strip()
    # An explicit editor correction may deliberately clear text. Do not turn
    # its retained section headings or poetry annotations into the verse again.
    if text or data.get("textEdited") is True:
        return text
    blocks = data.get("blocks_before")
    if not isinstance(blocks, list):
        return ""
    return " ".join(
        part for block in blocks if isinstance(block, dict)
        if (part := str(block.get("text") or "").strip())
    )
