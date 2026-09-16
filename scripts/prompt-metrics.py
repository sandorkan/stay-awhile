#!/usr/bin/env python3
"""Measure the last user message in a transcript. Pure stdlib.

Usage:  prompt-metrics.py <transcript.jsonl>
Prints one tab-separated line:

    words chars images paths code_blocks urls bullets questions is_slash

Counts only — never the text itself. Prints zeros and exits 0 on any problem:
this is telemetry, never a reason to break a hook.
"""

import json
import re
import sys

ZEROS = "\t".join(["0"] * 9)

# A path-ish token: has a slash, or a bare filename with a familiar extension.
PATH = re.compile(r"(?:\.{0,2}/)?[\w.-]+/[\w./-]+"
                  r"|\b[\w-]+\.(?:py|js|mjs|ts|tsx|jsx|sh|bash|zsh|json|jsonl|md|txt"
                  r"|wav|mp3|html|css|scss|go|rs|java|rb|php|c|h|cpp|sql|yml|yaml|toml|ini|cfg)\b")
BULLET = re.compile(r"(?m)^\s*(?:[-*+]|\d+[.)])\s+")


def last_user_message(path):
    """(text, image count) of the last real user message — tool results skipped."""
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - 512 * 1024))  # transcripts get long; the tail is enough
        lines = f.read().decode("utf-8", "replace").splitlines()
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") != "user":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            return content, 0
        if isinstance(content, list):
            text = "\n".join(b.get("text", "") for b in content
                             if isinstance(b, dict) and b.get("type") == "text")
            images = sum(1 for b in content
                         if isinstance(b, dict) and b.get("type") == "image")
            if text or images:  # a tool_result-only message isn't a prompt
                return text, images
    return None


def main():
    if len(sys.argv) < 2:
        return ZEROS
    found = last_user_message(sys.argv[1])
    if not found:
        return ZEROS
    text, images = found
    return "\t".join(str(n) for n in [
        len(text.split()),
        len(text),
        images,
        len(PATH.findall(text)),
        text.count("```") // 2,
        len(re.findall(r"https?://", text)),
        len(BULLET.findall(text)),
        text.count("?"),
        1 if text.lstrip().startswith("/") else 0,
    ])


if __name__ == "__main__":
    try:
        print(main())
    except Exception:
        print(ZEROS)
