#!/usr/bin/env python3
"""Рисует скрин терминала (тёмное окно) из текстового файла.
Первая строка файла считается строкой приглашения и подсвечивается.
Используется stand/scripts/shot.sh.
"""
import sys
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_SIZE = 16
COLS = 100
PAD = 16
LINE_SPACING = 4
BG = (24, 24, 28)
FG = (220, 220, 220)
PROMPT_FG = (120, 220, 140)
MAX_LINES = 60


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: render_term.py <input.txt> <output.png>", file=sys.stderr)
        return 1

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    raw_lines = src.read_text(encoding="utf-8", errors="replace").splitlines()

    wrapped: list[tuple[str, bool]] = []
    for idx, line in enumerate(raw_lines):
        is_prompt = idx == 0
        if not line:
            wrapped.append(("", is_prompt))
            continue
        for chunk in textwrap.wrap(
            line, width=COLS, replace_whitespace=False, drop_whitespace=False
        ) or [""]:
            wrapped.append((chunk, is_prompt))

    truncated = False
    if len(wrapped) > MAX_LINES:
        wrapped = wrapped[:MAX_LINES]
        truncated = True
    if truncated:
        wrapped.append(("… вывод обрезан, полный текст в .txt", False))

    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    char_w = font.getlength("M")
    line_h = FONT_SIZE + LINE_SPACING

    width = int(char_w * COLS) + PAD * 2
    height = line_h * len(wrapped) + PAD * 2

    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)

    y = PAD
    for text, is_prompt in wrapped:
        color = PROMPT_FG if is_prompt else FG
        draw.text((PAD, y), text, font=font, fill=color)
        y += line_h

    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
