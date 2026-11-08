"""M2-G2 normal-player-camera pass. Play mode, isolated review Studio only.

Walks the real character with character_navigation, rotates the default camera with
held arrow keys, zooms with the scroll wheel, captures the live camera (no
override) and reads the in-client logger (tools/review/cam_logger.luau).
    python tools/review/player_camera_pass.py [stop,stop,...]
"""
import base64
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "agent"))
sys.path.insert(0, HERE)
from client import StudioClient  # noqa: E402
from capture_review import foreground  # noqa: E402
import studio_review  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "docs", "evidence", "m2a1", "g2", "player-camera")
LOGGER = open(os.path.join(HERE, "cam_logger.luau"), encoding="utf-8").read()
# name: (stand point, why)
STOPS = {
    "porch": ((-6, 0, 19), "house entrance and porch"),
    "lane": ((-6, 0, 38), "narrow residential lane"),
    "arch": ((0, 0, 56), "street entrance arch (gapura)"),
    "kiosk": ((-6, 0, 63.5), "kiosk interaction distance"),
    "plaza": ((0, 0, 90), "plaza and fountain"),
    "return": ((-6, 0, 24), "return toward the house"),
}
c = StudioClient()
sid = studio_review.target(c)


def call(name, **args):
    return c.call_tool(name, dict(studio_id=sid, **args))


def luau(code, dm="Client"):
    r = call("execute_luau", code=code, datamodel_type=dm)
    return "\n".join(x.get("text", "") for x in r.get("content", []))


def mouse(actions):
    call("user_mouse_input", actions=actions, datamodel_type="Client")


def turn(ms, key="Left"):
    """Hold the default camera's arrow-key rotation (~118 deg/s). Real input, no CFrame writes."""
    call("user_keyboard_input", datamodel_type="Client", actions=[
        {"action": "keyDown", "key_code": key}, {"action": "wait", "wait_time_ms": ms},
        {"action": "keyUp", "key_code": key}])


def shot(name):
    r = call("screen_capture", capture_id=name)
    for item in r.get("content", []):
        if item.get("type") == "image":
            os.makedirs(OUT, exist_ok=True)
            path = os.path.join(OUT, name + ".png")
            open(path, "wb").write(base64.b64decode(item["data"]))
            return path
    raise SystemExit("no image for " + name)


def main():
    foreground("M2A1CityReview")
    luau(LOGGER)
    only = sys.argv[1].split(",") if len(sys.argv) > 1 else list(STOPS)
    for stop in only:
        (x, y, z), why = STOPS[stop]
        luau(LOGGER.replace("local mode = _G.M2A1_CAM_MODE or \"report\"", "local mode = 'reset'"))
        # Restore the default follow distance (12.7) so zoom does not leak between stops.
        luau("local p=game.Players.LocalPlayer p.CameraMinZoomDistance=12.7 p.CameraMaxZoomDistance=12.7 task.wait(0.5) p.CameraMinZoomDistance=0.5 p.CameraMaxZoomDistance=400")
        call("character_navigation", datamodel_type="Client", x=x, y=y, z=z)
        time.sleep(3)
        luau("local p=game.Players.LocalPlayer p.CameraMinZoomDistance=12.7 p.CameraMaxZoomDistance=12.7 task.wait(0.5) p.CameraMinZoomDistance=0.5 p.CameraMaxZoomDistance=400")
        luau(LOGGER.replace("local mode = _G.M2A1_CAM_MODE or \"report\"", "local mode = 'reset'"))
        print(f"== {stop}: {why}")
        shot(f"{stop}-0-default")
        for i in range(8):                      # sweep the camera through a full turn (~45 deg/step)
            turn(380)
            time.sleep(0.3)
            if i in (1, 3, 5):
                shot(f"{stop}-yaw{i + 1}")
        mouse([{"action": "scrollUp", "x": 700, "y": 320}] * 6)   # requested zoom-in steps
        time.sleep(0.4)
        shot(f"{stop}-zoomin")
        mouse([{"action": "scrollDown", "x": 700, "y": 320}] * 14)  # requested zoom-out steps
        time.sleep(0.6)
        shot(f"{stop}-zoomout")
        print(luau(LOGGER))
    foreground("M2A1CityReview")


if __name__ == "__main__":
    main()
