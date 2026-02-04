from pathlib import Path
from fnmatch import fnmatch

ROOT_DIR = Path(".")
MIN_LINES = 250

# Папки и паттерны файлов для исключения
EXCLUDED = """
    .build_cache
    .git
    __pycache__
    python
    android_build_env
    *.apk
    *.png
    *.idsig
""".split()


def is_excluded(path: Path) -> bool:
    for pattern in EXCLUDED:
        # проверяем части пути (папки)
        if any(part == pattern for part in path.parts):
            return True
        # проверяем паттерны (*.ext)
        if fnmatch(path.name, pattern):
            return True
    return False


for path in ROOT_DIR.rglob("*"):
    if is_excluded(path):
        continue

    if path.is_file():
        try:
            with path.open("r", encoding="utf-8", errors="ignore") as f:
                line_count = sum(1 for _ in f)

            if line_count > MIN_LINES:
                print(f"{path} : {line_count}")
        except OSError:
            pass
