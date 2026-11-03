"""Capture an explicitly selected, foreground Studio review instance."""
import argparse
import base64
import ctypes
import json
import pathlib
import time
from client import StudioClient


def foreground(title_fragment):
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    found = []
    def visit(hwnd, _):
        title = ctypes.create_unicode_buffer(1024)
        user32.GetWindowTextW(hwnd, title, 1024)
        if title_fragment in title.value and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True
    callback = callback_type(visit)
    user32.EnumWindows(callback, 0)
    if not found:
        raise RuntimeError("Review Studio window not found: " + title_fragment)
    hwnd = found[0]
    current = user32.GetForegroundWindow()
    foreground_thread = user32.GetWindowThreadProcessId(current, None)
    own_thread = ctypes.windll.kernel32.GetCurrentThreadId()
    attached = user32.AttachThreadInput(own_thread, foreground_thread, True)
    try:
        user32.ShowWindow(hwnd, 3)
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
    finally:
        if attached:
            user32.AttachThreadInput(own_thread, foreground_thread, False)
    time.sleep(0.5)
    if user32.GetForegroundWindow() != hwnd:
        raise RuntimeError("Windows denied foreground activation; no input sent")


def capture(studio_id, title, destination):
    foreground(title)
    client = StudioClient()
    try:
        result = client.call_tool("screen_capture", {"studio_id": studio_id, "capture_id": pathlib.Path(destination).stem})
        for item in result.get("content", []):
            if item.get("type") == "image":
                path = pathlib.Path(destination)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(base64.b64decode(item["data"]))
                print(str(path.resolve()))
                return
        raise RuntimeError(json.dumps(result))
    finally:
        client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("studio_id")
    parser.add_argument("destination")
    parser.add_argument("--title", default="BS12GameplayReview")
    args = parser.parse_args()
    capture(args.studio_id, args.title, args.destination)
