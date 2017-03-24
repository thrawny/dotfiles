#!/bin/bash
~/i3_scripts/i3subscribe.pl window | grep window:focus | \
while read -r line; do
    id="$(xprop -root _NET_ACTIVE_WINDOW | awk '{print $5}')"
    case "$(xprop -id "$id" WM_CLASS | cut -d\" -f4)" in
        slack)        kb=se ;;
        *)              kb=us ;;
    esac
    setxkbmap "$kb"
    xmodmap -e 'clear lock'
    xmodmap -e 'keycode 0x42=Escape'
    xmodmap -e 'keycode 94 = asciitilde asciitilde'
done
