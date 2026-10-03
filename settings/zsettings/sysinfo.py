"""sysinfo: сведения о системе для карточки «О системе» (DESIGN §4.4, Y6). Хук CLI: run(paths) -> dict.

Только чтение. Каждый источник независим: нет команды/файла — поле остаётся пустым, остальное работает.
"""
import json
import os
import re
import shutil
import subprocess

CMD_TIMEOUT = 5
# компоненты, наличие которых показывает блок «Компоненты» (команда -> подпись)
COMPONENTS = (
    ("nmcli", "NetworkManager"), ("bluetoothctl", "BlueZ"), ("wpctl", "PipeWire"),
    ("powerprofilesctl", "power-profiles-daemon"), ("brightnessctl", "brightnessctl"),
    ("hyprctl", "Hyprland"), ("qs", "Quickshell"), ("hypridle", "hypridle"), ("hyprlock", "hyprlock"),
    ("mpvpaper", "mpvpaper"), ("gio", "gio"), ("wl-copy", "wl-clipboard"), ("nm-connection-editor", "nm-connection-editor"),
)


def _cmd(argv):
    exe = shutil.which(argv[0])
    if exe is None:
        return None
    try:
        r = subprocess.run([exe] + argv[1:], capture_output=True, text=True, timeout=CMD_TIMEOUT,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_os_release(text):
    out = {}
    for ln in (text or "").splitlines():
        m = re.match(r'^([A-Z_]+)=(.*)$', ln.strip())
        if m:
            out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return out


def parse_meminfo(text):
    """-> (total_kib, available_kib)."""
    vals = {}
    for ln in (text or "").splitlines():
        m = re.match(r'^(\w+):\s+(\d+)', ln)
        if m:
            vals[m.group(1)] = int(m.group(2))
    return vals.get("MemTotal"), vals.get("MemAvailable")


def parse_cpu(text):
    for ln in (text or "").splitlines():
        if ln.startswith("model name"):
            return re.sub(r'\s+', ' ', ln.split(":", 1)[1]).strip()
    return ""


def parse_uptime(text):
    try:
        return int(float((text or "").split()[0]))
    except (IndexError, ValueError):
        return None


def parse_lspci_gpus(text):
    """Строки `lspci` с VGA/3D/Display-контроллерами -> список «Производитель Модель»."""
    out = []
    for ln in (text or "").splitlines():
        m = re.match(r'^\S+\s+(VGA compatible controller|3D controller|Display controller):\s*(.+)$', ln)
        if m:
            name = re.sub(r'\s*\(rev [0-9a-f]+\)\s*$', '', m.group(2)).strip()
            out.append(name)
    return out


def _first_line(text):
    for ln in (text or "").splitlines():
        if ln.strip():
            return ln.strip()
    return ""


def hypr_version(text):
    try:
        v = json.loads(text)
        return str(v.get("version") or v.get("tag") or "").lstrip("v")
    except (ValueError, AttributeError):
        m = re.search(r'v?(\d+\.\d+(\.\d+)?)', text or "")
        return m.group(1) if m else ""


def qs_version(text):
    m = re.search(r'(\d+\.\d+(\.\d+)?)', text or "")
    return m.group(1) if m else ""


def _hostname():
    out = _cmd(["hostnamectl", "--json=short"])
    if out:
        try:
            return json.loads(out).get("Hostname") or ""
        except ValueError:
            pass
    return (_read("/etc/hostname") or "").strip() or os.uname().nodename


def collect():
    osr = parse_os_release(_read("/etc/os-release"))
    total, avail = parse_meminfo(_read("/proc/meminfo"))
    return {
        "hostname": _hostname(),
        "os": osr.get("PRETTY_NAME") or osr.get("NAME") or "",
        "kernel": os.uname().release,
        "hyprland": hypr_version(_cmd(["hyprctl", "version", "-j"]) or ""),
        "quickshell": qs_version(_cmd(["qs", "--version"]) or ""),
        "cpu": parse_cpu(_read("/proc/cpuinfo")),
        "memTotalKiB": total,
        "memAvailableKiB": avail,
        "uptimeSec": parse_uptime(_read("/proc/uptime")),
        "gpus": parse_lspci_gpus(_cmd(["lspci"]) or ""),
        "components": [{"cmd": c, "label": label, "present": shutil.which(c) is not None} for c, label in COMPONENTS],
    }


def summary_text(info):
    """Текст для кнопки «Скопировать»."""
    lines = ["%s · %s · Linux %s" % (info.get("hostname") or "?", info.get("os") or "?", info.get("kernel") or "?")]
    parts = []
    if info.get("hyprland"):
        parts.append("Hyprland " + info["hyprland"])
    if info.get("quickshell"):
        parts.append("Quickshell " + info["quickshell"])
    if parts:
        lines.append(" · ".join(parts))
    if info.get("cpu"):
        lines.append("CPU: " + info["cpu"])
    if info.get("memTotalKiB"):
        lines.append("RAM: %.1f ГиБ" % (info["memTotalKiB"] / 1048576.0))
    for g in info.get("gpus") or []:
        lines.append("GPU: " + g)
    return "\n".join(lines)


def run(paths):
    info = collect()
    info["text"] = summary_text(info)
    info["ok"] = True
    return info
