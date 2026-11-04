import sys
sys.path.append('tools/agent')
import studio

mode = sys.argv[1] if len(sys.argv) > 1 else 'state'
if mode == 'state':
    print(studio.call("get_studio_state", {}))
elif mode == 'edit':
    print(studio.luau('return game.Name .. "|" .. tostring(game.PlaceId)', 'Edit'))
elif mode == 'play':
    print(studio.call("start_stop_play", {"is_start": True}))
elif mode == 'stop':
    print(studio.call("start_stop_play", {"is_start": False}))
elif mode == 'console':
    print(studio.call("get_console_output", {}))
