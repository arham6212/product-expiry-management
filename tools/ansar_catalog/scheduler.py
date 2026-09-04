from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess

from .config import LOG_DIR, PROJECT_ROOT

LABEL = "com.openai.ansar-catalog"


def command(project_root: Path) -> list[str]:
    return [shutil.which("python3") or "python3", "-m", "tools.ansar_catalog.cli", "run_once"]


def install_launchd(project_root: Path) -> Path:
    target = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
    target.parent.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "Label": LABEL, "ProgramArguments": command(project_root),
        "WorkingDirectory": str(project_root), "StartInterval": 18000,
        "RunAtLoad": True,
        "StandardOutPath": str(LOG_DIR / "scheduler.out.log"),
        "StandardErrorPath": str(LOG_DIR / "scheduler.err.log"),
    }
    with target.open("wb") as handle:
        plistlib.dump(payload, handle)
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", str(target)], check=False, capture_output=True)
    subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)], check=True)
    return target


def install_systemd(project_root: Path) -> tuple[Path, Path]:
    unit_dir = Path.home() / ".config" / "systemd" / "user"
    unit_dir.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    service = unit_dir / "ansar-catalog.service"
    timer = unit_dir / "ansar-catalog.timer"
    service.write_text(
        "[Unit]\nDescription=Ansar Gallery catalog crawler batch\n\n[Service]\nType=oneshot\n"
        f"WorkingDirectory={project_root}\nExecStart={' '.join(command(project_root))}\n",
        encoding="utf-8",
    )
    timer.write_text(
        "[Unit]\nDescription=Run Ansar catalog crawler every five hours\n\n[Timer]\n"
        "OnBootSec=5min\nOnUnitActiveSec=5h\nPersistent=true\nUnit=ansar-catalog.service\n\n"
        "[Install]\nWantedBy=timers.target\n",
        encoding="utf-8",
    )
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "enable", "--now", "ansar-catalog.timer"], check=True)
    return service, timer


def uninstall() -> None:
    if platform.system() == "Darwin":
        target = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
        subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}", str(target)], check=False)
        target.unlink(missing_ok=True)
    else:
        subprocess.run(["systemctl", "--user", "disable", "--now", "ansar-catalog.timer"], check=False)
        unit_dir = Path.home() / ".config" / "systemd" / "user"
        (unit_dir / "ansar-catalog.service").unlink(missing_ok=True)
        (unit_dir / "ansar-catalog.timer").unlink(missing_ok=True)
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)


def generate_templates(project_root: Path) -> list[Path]:
    out = project_root / "tools" / "ansar_catalog" / "scheduler"
    out.mkdir(parents=True, exist_ok=True)
    service = out / "ansar-catalog.service.example"
    timer = out / "ansar-catalog.timer.example"
    plist = out / f"{LABEL}.plist.example"
    service.write_text(
        "[Unit]\nDescription=Ansar Gallery catalog crawler batch\n\n[Service]\nType=oneshot\n"
        f"WorkingDirectory={project_root}\nExecStart={' '.join(command(project_root))}\n", encoding="utf-8")
    timer.write_text(
        "[Unit]\nDescription=Run Ansar catalog crawler every five hours\n\n[Timer]\n"
        "OnBootSec=5min\nOnUnitActiveSec=5h\nPersistent=true\nUnit=ansar-catalog.service\n\n"
        "[Install]\nWantedBy=timers.target\n", encoding="utf-8")
    with plist.open("wb") as handle:
        plistlib.dump({
            "Label": LABEL, "ProgramArguments": command(project_root), "WorkingDirectory": str(project_root),
            "StartInterval": 18000, "RunAtLoad": True,
            "StandardOutPath": str(LOG_DIR / "scheduler.out.log"),
            "StandardErrorPath": str(LOG_DIR / "scheduler.err.log"),
        }, handle)
    return [service, timer, plist]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["install", "uninstall", "generate"])
    parser.add_argument("--project-root", type=Path, default=PROJECT_ROOT)
    args = parser.parse_args()
    root = args.project_root.resolve()
    if args.action == "uninstall":
        uninstall(); print("scheduler stopped and removed"); return 0
    if args.action == "generate":
        print("\n".join(map(str, generate_templates(root)))); return 0
    if platform.system() == "Darwin":
        print(install_launchd(root))
    elif shutil.which("systemctl"):
        print("\n".join(map(str, install_systemd(root))))
    else:
        raise RuntimeError("No launchd or systemd user scheduler is available; use generated templates on a supported host")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

