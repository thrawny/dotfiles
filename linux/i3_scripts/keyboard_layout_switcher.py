#!/usr/bin/env python3

import os

import i3ipc


def switch_lang(lang: str):
    return os.system("setxkbmap {} && . ~/.xsessionrc".format(lang))


def on_window_focus(i3: i3ipc.Connection, e: i3ipc.WorkspaceEvent):
    focused = i3.get_tree().find_focused()
    if focused.window_class == "Slack":
        switch_lang("se")
    else:
        switch_lang("us")


if __name__ == "__main__":
    conn = i3ipc.Connection()
    conn.on("workspace::focus", on_window_focus)
    conn.main()
