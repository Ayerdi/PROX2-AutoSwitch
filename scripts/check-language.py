"""Fail CI when Spanish prose leaks outside the bilingual Wiki source.

English is the canonical repository language. Spanish is intentionally allowed
under wiki/ for the maintained Spanish Wiki edition. Legacy filenames may stay
for backward compatibility; this checker inspects contents rather than paths.
"""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".venv", "__pycache__", "wiki"}
SKIP_FILES = {Path("scripts/check-language.py")}
TEXT_SUFFIXES = {
    ".cmd", ".css", ".html", ".js", ".json", ".md", ".ps1", ".psm1",
    ".py", ".sh", ".txt", ".vbs", ".yaml", ".yml", ".csv",
}
TEXT_NAMES = {"LICENSE"}

SPANISH_PATTERNS = [
    re.compile(r"[áéíóúüñ¿¡]", re.IGNORECASE),
    re.compile(
        r"\b(?:"
        r"no debe|no se puede|no esta|debe ser|se agreg[oó]|se reintentara|"
        r"auricular(?:es)?|altavoces?|bandeja|instalaci[oó]n|desinstalaci[oó]n|"
        r"configuraci[oó]n|reconfiguraci[oó]n|verificaci[oó]n|conectado|desconectado|"
        r"encendido|apagado|selecciona|seleccionar|salida de audio|"
        r"prueba|modo universal|versi[oó]n estable|exportacion|transicion|"
        r"reconexion|icono|notificaciones|hilo|bucle|unico|lectura|migracion|"
        r"peticion|esperando|cerro|limite global|eventos asincronos|devuelve|"
        r"detectado|segundo intento|consiguio|estado del endpoint|exporta|fila|"
        r"ausente|desconocido|preseleccionar|cambio fisico|ultimo estado|"
        r"encontrado por|nuevo item|reintentar|submen[uú]"
        r")\b",
        re.IGNORECASE,
    ),
]

# These words are deliberately chosen for low overlap with normal English code.
# Two matches on the same line are enough to flag likely Spanish prose.
SPANISH_STOPWORDS = {
    "aqui", "antes", "bajo", "cada", "cuando", "debe", "deben", "del",
    "desde", "despues", "donde", "esta", "este", "esto", "hasta", "la", "las",
    "los", "para", "pero", "por", "porque", "que", "sin", "solo", "tambien",
    "una", "uno", "varios", "ya",
}

# Localized labels and multilingual input literals are compatibility metadata,
# not repository prose. Keep them while requiring surrounding documentation to
# remain English.
ALLOWED_FRAGMENTS = ("Español",)
ALLOWED_LINE_PATTERNS = (
    re.compile(r"\^\(s\|si\|sí\|y\|yes\)\$", re.IGNORECASE),
)


def strip_diacritics(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(c for c in normalized if not unicodedata.combining(c))


def is_text_file(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if relative in SKIP_FILES:
        return False
    if any(part in SKIP_DIRS for part in relative.parts[:-1]):
        return False
    return path.name in TEXT_NAMES or path.suffix.lower() in TEXT_SUFFIXES


def looks_spanish(line: str) -> bool:
    if any(pattern.search(line) for pattern in ALLOWED_LINE_PATTERNS):
        return False
    candidate = line
    for fragment in ALLOWED_FRAGMENTS:
        candidate = candidate.replace(fragment, "Spanish")
    if any(pattern.search(candidate) for pattern in SPANISH_PATTERNS):
        return True
    words = re.findall(r"[a-z]+", strip_diacritics(candidate).casefold())
    return sum(word in SPANISH_STOPWORDS for word in words) >= 2


def main() -> int:
    findings: list[str] = []
    checked = 0
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or not is_text_file(path):
            continue
        checked += 1
        try:
            text = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            if looks_spanish(line):
                findings.append(f"{path.relative_to(ROOT)}:{line_number}: {line.strip()}")

    if findings:
        print("Spanish prose found outside wiki/:")
        print("\n".join(findings))
        return 1

    print(f"Language check OK: {checked} text files checked; Spanish is confined to wiki/.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
