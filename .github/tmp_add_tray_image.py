from pathlib import Path
import sys

IMAGE_URL = "https://ayerdi.github.io/PROX2-AutoSwitch/assets/tray-menu.png"


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f"{label}: marker not found")
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one marker, found {text.count(old)}")
    return text.replace(old, new, 1)


def update_repo():
    # README
    p = Path("README.md")
    t = read(p)
    image_ref = "site/assets/tray-menu.png"
    if image_ref not in t:
        marker = "Once running, an icon appears in the system tray:\n"
        block = (
            marker
            + "\n![Audio AutoSwitch tray menu showing headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements and Reconfigure](site/assets/tray-menu.png)\n\n"
            + "*Example tray menu with a Logitech PRO X 2 configured: headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit are all available without opening a separate window.*\n"
        )
        t = replace_once(t, marker, block, "README tray image")
        write(p, t)

    # GitHub Pages
    p = Path("site/index.html")
    t = read(p)
    if 'src="assets/tray-menu.png"' not in t:
        marker = "      <!-- why -->"
        block = '''      <!-- tray menu -->
      <section id="tray" class="section">
        <div class="section-head">
          <h2 data-i18n="trayTitle"></h2>
          <p class="lead" data-i18n="trayCaption"></p>
        </div>
        <figure style="margin: 1.25rem 0 0;">
          <img src="assets/tray-menu.png" alt="Audio AutoSwitch tray menu showing the configured headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit" style="display:block;max-width:100%;height:auto;border:1px solid var(--border);border-radius:12px;">
          <figcaption class="muted" data-i18n="trayFigureCaption" style="margin-top:.65rem;"></figcaption>
        </figure>
      </section>

'''
        t = replace_once(t, marker, block + marker, "site tray section")

        es_marker = '        demo3: "La app corre en segundo plano, sin ventana de PowerShell al iniciar sesión.",\n'
        es_add = es_marker + '        trayTitle: "El menú de la bandeja",\n        trayCaption: "De un vistazo puedes ver el headset, la salida alternativa y el próximo cambio, pausar AutoSwitch, gestionar Audio Enhancements y abrir Reconfigure.",\n        trayFigureCaption: "Ejemplo real con un Logitech PRO X 2 configurado.",\n'
        t = replace_once(t, es_marker, es_add, "site ES tray strings")

        en_marker = '        demo3: "Runs quietly in the background — no PowerShell window at login.",\n'
        en_add = en_marker + '        trayTitle: "The tray menu",\n        trayCaption: "At a glance you can see the headset, fallback output and next switch, pause AutoSwitch, manage Audio Enhancements and open Reconfigure.",\n        trayFigureCaption: "Real example with a Logitech PRO X 2 configured.",\n'
        t = replace_once(t, en_marker, en_add, "site EN tray strings")
        write(p, t)

    # Changelog: current-main documentation change, not v1.2.3 release history.
    p = Path("CHANGELOG.md")
    t = read(p)
    bullet = "- Added a real tray-menu screenshot to README, GitHub Pages and Wiki so users can see the runtime controls before installing.\n"
    if bullet not in t:
        marker = "- README, GitHub Pages, maintainer notes, security/source notes and the historical WindowsEndpoint design document were refreshed to match the post-v1.2.3 behavior and hardware findings.\n"
        t = replace_once(t, marker, marker + bullet, "CHANGELOG tray screenshot")
        write(p, t)


def insert_after_h1(text, block):
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith("# "):
            lines.insert(i + 1, "\n" + block + "\n")
            return "".join(lines)
    raise SystemExit("wiki: no H1 found")


def update_wiki(root):
    root = Path(root)
    pages = {
        "Home.md": (
            f"![Audio AutoSwitch tray menu]({IMAGE_URL})\n\n"
            "*Tray menu / Menú de bandeja — example with a PRO X 2 configured: current headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit.*\n"
        ),
        "Verificar-ES.md": (
            f"![Menú de bandeja de Audio AutoSwitch]({IMAGE_URL})\n\n"
            "*Ejemplo real con un PRO X 2 configurado. El menú muestra el headset, fallback, próximo cambio y los controles de AutoSwitch.*\n"
        ),
        "Verify-EN.md": (
            f"![Audio AutoSwitch tray menu]({IMAGE_URL})\n\n"
            "*Real example with a PRO X 2 configured. The menu exposes the headset, fallback, next switch and AutoSwitch controls.*\n"
        ),
    }
    for name, block in pages.items():
        p = root / name
        t = p.read_text(encoding="utf-8")
        if IMAGE_URL not in t:
            p.write_text(insert_after_h1(t, block), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: tmp_add_tray_image.py repo | wiki <path>")
    if sys.argv[1] == "repo":
        update_repo()
    elif sys.argv[1] == "wiki" and len(sys.argv) == 3:
        update_wiki(sys.argv[2])
    else:
        raise SystemExit("invalid arguments")
