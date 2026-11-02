import sys
import os
import time

sys.path.append(os.path.abspath("tools/agent"))
import studio

studio.call('start_stop_play', {'is_start': True})
time.sleep(3.0)
out = studio.call('get_console_output', {})
studio.call('start_stop_play', {'is_start': False})

for line in out.splitlines():
    if 'SUITE' in line or 'TESTS_PASSED' in line or 'TESTS_FAILED' in line:
        print(line)
