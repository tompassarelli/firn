"""Type stdin into a private desktop over VNC: private-desktop-type.py PORT."""
import string
import sys
import time

SHIFT = 0xFFE1
# wayvnc maps a keysym to its unshifted keycode, so a shifted character is sent
# as Shift held around its US-layout base key.
SHIFTED = dict(zip('~!@#$%^&*()_+{}|:"<>?', "`1234567890-=[]\\;',./"))
NAMED = {"\n": 0xFF0D, "\t": 0xFF09}
PLAIN = set(string.ascii_lowercase + string.digits + " `-=[]\\;',./")


def plan(text):
    """Return one (shift, keysym) per character; refuse text a US layout cannot type."""
    keys = []
    for position, character in enumerate(text):
        if character in NAMED:
            keys.append((False, NAMED[character]))
        elif character in PLAIN:
            keys.append((False, ord(character)))
        elif character in string.ascii_uppercase:
            keys.append((True, ord(character.lower())))
        elif character in SHIFTED:
            keys.append((True, ord(SHIFTED[character])))
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
        for shift, keysym in keys:
            if shift:
                client.keyEvent(SHIFT, down=True)
            client.keyEvent(keysym, down=True)
            client.keyEvent(keysym, down=False)
            if shift:
                client.keyEvent(SHIFT, down=False)
            time.sleep(0.08)
    finally:
        client.disconnect()
        api.shutdown()


if __name__ == "__main__":
    main()
