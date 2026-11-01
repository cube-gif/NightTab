#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Приводит ширину изображений в папке скрипта к 2560 px.

- ширина > 2560: исходник копируется в _originals/, файл уменьшается;
- ширина < 2560: файл растягивается (исходник не сохраняется);
- ширина = 2560: файл пропускается.

Пропорции сохраняются. Повторный запуск безопасен: готовые файлы
шириной 2560 px уже не трогаются.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageOps, ImageSequence

TARGET_WIDTH = 2560
ORIGINALS_DIR = "_originals"
QUALITY = 90

FORMATS = {
    ".jpg": "JPEG",
    ".jpeg": "JPEG",
    ".png": "PNG",
    ".webp": "WEBP",
    ".gif": "GIF",
    ".bmp": "BMP",
    ".tif": "TIFF",
    ".tiff": "TIFF",
    ".avif": "AVIF",
}

try:
    LANCZOS = Image.Resampling.LANCZOS
except AttributeError:  # Pillow < 9.1
    LANCZOS = Image.LANCZOS


def log(message: str) -> None:
    print(message, flush=True)


def resize_to_width(image: Image.Image, width: int = TARGET_WIDTH) -> Image.Image:
    height = max(1, round(image.height * width / image.width))
    return image.resize((width, height), LANCZOS)


def backup_original(path: Path, originals_dir: Path, dry_run: bool) -> None:
    destination = originals_dir / path.name
    if destination.exists():
        log(f"  original already in {ORIGINALS_DIR}: {path.name}")
        return
    log(f"  original -> {ORIGINALS_DIR}/{path.name}")
    if not dry_run:
        originals_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)


def replace_temp(temp_path: Path, path: Path) -> None:
    try:
        os.replace(temp_path, path)
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


def save_static(image: Image.Image, path: Path, image_format: str) -> None:
    options: dict = {}
    icc_profile = image.info.get("icc_profile")
    if icc_profile:
        options["icc_profile"] = icc_profile

    if image_format == "JPEG":
        if image.mode not in ("RGB", "L"):
            image = image.convert("RGB")
        options.update(quality=QUALITY, optimize=True, progressive=True)
    elif image_format == "WEBP":
        options.update(quality=QUALITY, method=6)
    elif image_format == "AVIF":
        options.update(quality=QUALITY)
    elif image_format == "PNG":
        options.update(optimize=True, compress_level=9)
    elif image_format == "GIF":
        options.update(optimize=True)
    elif image_format == "TIFF":
        options.update(compression="tiff_lzw")

    temp_path = path.with_name(path.name + ".tmp")
    image.save(temp_path, format=image_format, **options)
    replace_temp(temp_path, path)


def save_animated(image: Image.Image, path: Path, image_format: str) -> None:
    frames = []
    durations = []
    loop = image.info.get("loop", 0)

    for frame in ImageSequence.Iterator(image):
        duration = frame.info.get("duration", image.info.get("duration", 100))
        durations.append(duration)
        if image_format == "GIF":
            # GIF-кадры должны быть в палитровом режиме.
            frames.append(resize_to_width(frame.convert("RGBA")).convert("P", palette=Image.ADAPTIVE))
        else:
            frames.append(resize_to_width(frame.convert("RGBA")))

    options: dict = {
        "save_all": True,
        "append_images": frames[1:],
        "duration": durations,
        "loop": loop,
    }
    if image_format == "WEBP":
        options.update(quality=QUALITY, method=6)
    elif image_format == "GIF":
        options.update(optimize=True, disposal=2)
    elif image_format == "PNG":
        options.update(optimize=True)

    temp_path = path.with_name(path.name + ".tmp")
    # На Windows исходный файл должен быть закрыт до os.replace.
    image.close()
    frames[0].save(temp_path, format=image_format, **options)
    replace_temp(temp_path, path)


def process(path: Path, originals_dir: Path, dry_run: bool) -> str:
    image_format = FORMATS[path.suffix.lower()]

    with Image.open(path) as image:
        frame_count = getattr(image, "n_frames", 1)
        animated = frame_count > 1

        if animated and image_format not in ("GIF", "WEBP", "PNG", "AVIF"):
            return f"skip (animated {image_format}): {path.name}"

        if not animated:
            image = ImageOps.exif_transpose(image)

        width = image.width
        if width == TARGET_WIDTH:
            return f"skip (already {width}px): {path.name}"

        if width > TARGET_WIDTH:
            action = "downscale"
        else:
            action = "upscale"

        result = f"{action} {width}->{TARGET_WIDTH}: {path.name}"

        if width > TARGET_WIDTH:
            backup_original(path, originals_dir, dry_run)

        if dry_run:
            return result

        if animated:
            save_animated(image, path, image_format)
        else:
            save_static(resize_to_width(image), path, image_format)

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Привести ширину изображений к 2560 px.")
    parser.add_argument("--dry-run", action="store_true", help="показать действия без изменения файлов")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent
    originals_dir = root / ORIGINALS_DIR

    processed = skipped = failed = 0
    for path in sorted(root.iterdir()):
        if not path.is_file() or path.suffix.lower() not in FORMATS:
            continue
        try:
            message = process(path, originals_dir, args.dry_run)
            log(("[dry-run] " if args.dry_run else "") + message)
            if message.startswith("skip"):
                skipped += 1
            else:
                processed += 1
        except Exception as error:  # noqa: BLE001 - хотим обработать все файлы
            failed += 1
            log(f"ERROR {path.name}: {error}")

    suffix = " (dry-run)" if args.dry_run else ""
    log(f"Done{suffix}: processed={processed}, skipped={skipped}, failed={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass
    raise SystemExit(main())
