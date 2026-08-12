from pathlib import Path
import sys

IMAGE_URL = "https://ayerdi.github.io/PROX2-AutoSwitch/assets/tray-menu.png"


def rd(p):
    return Path(p).read_text(encoding="utf-8-sig")


def wr(p, s):
    Path(p).write_text(s, encoding="utf-8")


def add_after_once(text, marker, addition, label):
    if addition.strip() in text:
        return text
    if text.count(marker) != 1:
        raise SystemExit(f"{label}: expected one marker, got {text.count(marker)}")
    return text.replace(marker, marker + addition, 1)


def repo():
    p = "README.md"
    t = rd(p)
    if "site/assets/tray-menu.png" not in t:
        marker = "Once running, an icon appears in the system tray:\n"
        addition = "\n![Audio AutoSwitch tray menu showing headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements and Reconfigure](site/assets/tray-menu.png)\n\n*Example tray menu with a Logitech PRO X 2 configured: headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit are all available without opening a separate window.*\n"
        t = add_after_once(t, marker, addition, "README")
        wr(p, t)

    p = "site/index.html"
    t = rd(p)
    if 'src="assets/tray-menu.png"' not in t:
        marker = "      <!-- why -->"
        section = '''      <!-- tray menu -->
      <section id="tray" class="section">
        <div class="section-head">
          <h2 data-i18n="trayTitle"></h2>
          <p class="lead" data-i18n="trayCaption"></p>
        </div>
        <figure style="margin:1.25rem 0 0;">
          <img src="assets/tray-menu.png" alt="Audio AutoSwitch tray menu showing the configured headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit" style="display:block;max-width:100%;height:auto;border:1px solid var(--border);border-radius:12px;">
          <figcaption class="muted" data-i18n="trayFigureCaption" style="margin-top:.65rem;"></figcaption>
        </figure>
      </section>

'''
        if t.count(marker) != 1:
            raise SystemExit("site section marker mismatch")
        t = t.replace(marker, section + marker, 1)
    if 'trayTitle: "El menú de la bandeja"' not in t:
        marker = '        demo3: "La app corre en segundo plano, sin ventana de PowerShell al iniciar sesión.",\n'
        addition = '        trayTitle: "El menú de la bandeja",\n        trayCaption: "De un vistazo puedes ver el headset, la salida alternativa y el próximo cambio, pausar AutoSwitch, gestionar Audio Enhancements y abrir Reconfigure.",\n        trayFigureCaption: "Ejemplo real con un Logitech PRO X 2 configurado.",\n'
        t = add_after_once(t, marker, addition, "site ES")
    if 'trayTitle: "The tray menu"' not in t:
        marker = '        demo3: "Runs quietly in the background — no PowerShell window at login.",\n'
        addition = '        trayTitle: "The tray menu",\n        trayCaption: "At a glance you can see the headset, fallback output and next switch, pause AutoSwitch, manage Audio Enhancements and open Reconfigure.",\n        trayFigureCaption: "Real example with a Logitech PRO X 2 configured.",\n'
        t = add_after_once(t, marker, addition, "site EN")
    wr(p, t)

    p = "CHANGELOG.md"
    t = rd(p)
    bullet = "- Added a real tray-menu screenshot to README, GitHub Pages and Wiki so users can see the runtime controls before installing.\n"
    if bullet not in t:
        marker = "- README, GitHub Pages, maintainer notes, security/source notes and the historical WindowsEndpoint design document were refreshed to match the post-v1.2.3 behavior and hardware findings.\n"
        t = add_after_once(t, marker, bullet, "CHANGELOG")
        wr(p, t)


def wiki(root):
    root = Path(root)
    blocks = {
        "Home.md": f"![Audio AutoSwitch tray menu]({IMAGE_URL})\n\n*Tray menu / Menú de bandeja — example with a PRO X 2 configured: current headset, fallback, next switch, AutoSwitch toggle, Audio Enhancements, Reconfigure and Exit.*\n",
        "Verificar-ES.md": f"![Menú de bandeja de Audio AutoSwitch]({IMAGE_URL})\n\n*Ejemplo real con un PRO X 2 configurado. El menú muestra el headset, fallback, próximo cambio y los controles de AutoSwitch.*\n",
        "Verify-EN.md": f"![Audio AutoSwitch tray menu]({IMAGE_URL})\n\n*Real example with a PRO X 2 configured. The menu exposes the headset, fallback, next switch and AutoSwitch controls.*\n",
    }
    for name, block in blocks.items():
        p = root / name
        t = p.read_text(encoding="utf-8")
        if IMAGE_URL in t:
            continue
        lines = t.splitlines(keepends=True)
        for i, line in enumerate(lines):
            if line.startswith("# "):
                lines.insert(i + 1, "\n" + block + "\n")
                p.write_text("".join(lines), encoding="utf-8")
                break
        else:
            raise SystemExit(f"{name}: H1 missing")


if __name__ == "__main__":
    if sys.argv[1:] == ["repo"]:
        repo()
    elif len(sys.argv) == 3 and sys.argv[1] == "wiki":
        wiki(sys.argv[2])
    else:
        raise SystemExit("bad args")
