#!/usr/bin/env python3
"""Convert WOFF/WOFF2 web-font containers to Android-usable SFNT without renaming bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from fontTools.ttLib import TTFont

MAGIC = {b"wOFF": "WOFF", b"wOF2": "WOFF2"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_stem(value: str) -> str:
    cleaned = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in value)
    cleaned = cleaned.strip(".-_")
    return cleaned[:80] or "ConvertedFont"


def output_extension(font: TTFont) -> str:
    if "glyf" in font:
        return "ttf"
    if "CFF " in font or "CFF2" in font:
        return "otf"
    raise ValueError("网页字体不包含 Android 支持的 glyf/CFF/CFF2 轮廓")


def validate_sfnt(path: Path) -> str:
    with path.open("rb") as stream:
        magic = stream.read(4)
    if magic in (b"\x00\x01\x00\x00", b"true", b"\x00\x02\x00\x00"):
        return "TTF"
    if magic == b"OTTO":
        return "OTF"
    raise ValueError("转换结果不是有效 SFNT 字体")


def convert(source: Path, output_dir: Path) -> dict[str, Any]:
    if not source.is_file() or source.stat().st_size < 12:
        raise ValueError("网页字体文件不存在或过小")
    with source.open("rb") as stream:
        container = MAGIC.get(stream.read(4))
    if container is None:
        raise ValueError("仅支持 WOFF / WOFF2 转换")

    try:
        font = TTFont(str(source), lazy=False, recalcTimestamp=False)
    except Exception as error:
        if container == "WOFF2":
            raise ValueError(f"WOFF2 解码失败，运行时可能缺少 Brotli 支持：{error}") from error
        raise

    try:
        ext = output_extension(font)
        font.flavor = None
        source_hash = sha256(source)
        target = output_dir / f"{safe_stem(source.stem)}-{source_hash[:10]}.{ext}"
        output_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            prefix=target.name + ".", suffix=".tmp", dir=output_dir, delete=False
        ) as handle:
            temp = Path(handle.name)
        try:
            font.save(str(temp), reorderTables=False)
            if temp.stat().st_size < 4096:
                raise ValueError("转换结果异常为空")
            output_format = validate_sfnt(temp)
            # Re-open the produced file so a successful save alone cannot masquerade
            # as a valid Android font.
            check = TTFont(str(temp), lazy=True, recalcTimestamp=False)
            try:
                if "cmap" not in check or "head" not in check:
                    raise ValueError("转换结果缺少 cmap/head")
            finally:
                check.close()
            output_hash = sha256(temp)
            duplicate = target.is_file() and sha256(target) == output_hash
            if duplicate:
                temp.unlink(missing_ok=True)
            else:
                os.chmod(temp, 0o644)
                os.replace(temp, target)
            return {
                "status": "ok",
                "sourceContainer": container,
                "sourceSha256": source_hash,
                "outputFormat": output_format,
                "outputSha256": output_hash,
                "outputPath": str(target),
                "outputFileName": target.name,
                "duplicate": duplicate,
            }
        finally:
            temp.unlink(missing_ok=True)
    finally:
        font.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = convert(args.input, args.output_dir)
    except Exception as error:
        print(json.dumps({"status": "error", "message": str(error)}, ensure_ascii=False, separators=(",", ":")))
        return 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
