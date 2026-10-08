"""Type stdin into a private desktop over VNC: private-desktop-type.py PORT."""
import string
import sys
import time

# wayvnc sets Shift only as a modifier state, which Wine apps ignore (@ arrives
# as 2), so a shifted character is sent with a real Shift key held around it.
SHIFTED = set('~!@#$%^&*()_+{}|:"<>?' + string.ascii_uppercase)
NAMED = {"\n": "enter", "\t": "tab"}
PLAIN = set(string.ascii_lowercase + string.digits + " `-=[]\\;',./")


def plan(text):
    """Return one (shift, vncdotool key) per character; refuse text a US layout cannot type."""
    keys = []
    for position, character in enumerate(text):
        if character in NAMED:
            keys.append((False, NAMED[character]))
        elif character in PLAIN:
            keys.append((False, character))
        elif character in SHIFTED:
            keys.append((True, character))
        else:
            raise ValueError(f"character {position + 1} has no US-layout key")
    return keys


def main():
    port = sys.argv[1]
    try:
        keys = plan(sys.stdin.read())
    except ValueError as error:
        sys.exit(f"private-desktop: {error}; nothing was typed")
    from vncdotool import api

    client = api.connect(f"127.0.0.1::{port}", timeout=20)
    try:
        # keyDown/keyUp, not keyEvent: they return the client, which keeps
        # vncdotool's per-call connection chain alive.
        for shift, key in keys:
            if shift:
                client.keyDown("shift")
            client.keyDown(key)
            client.keyUp(key)
            if shift:
                client.keyUp("shift")
            time.sleep(0.08)
    finally:
        client.disconnect()
        api.shutdown()


if __name__ == "__main__":
    main()
