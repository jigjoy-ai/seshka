#!/usr/bin/python3
"""Generates the full-color logo in design/color/.

  closed.svg, open.svg            app icon: the doll on its rounded background
  closed-mark.svg, open-mark.svg  the doll alone, for use inside the app
"""
import os

DOLL = "M12 2C14.6 2 16.3 4 16.3 6.4C16.3 8 16.1 9.4 15.7 10.4C17.4 11.4 18.5 13.2 18.7 15.2C18.9 17.6 18.3 20.4 17.2 22L6.8 22C5.7 20.4 5.1 17.6 5.3 15.2C5.5 13.2 6.6 11.4 8.3 10.4C7.9 9.4 7.7 8 7.7 6.4C7.7 4 9.4 2 12 2Z"
TOP = "M12 2C14.6 2 16.3 4 16.3 6.4C16.3 8 16.1 9.4 15.7 10.4C17.4 11.4 18.5 13.1 18.66 14.6L5.34 14.6C5.5 13.1 6.6 11.4 8.3 10.4C7.9 9.4 7.7 8 7.7 6.4C7.7 4 9.4 2 12 2Z"
BOTTOM = "M5.3 15.9L18.7 15.9C18.9 17.9 18.3 20.5 17.2 22L6.8 22C5.7 20.5 5.1 17.9 5.3 15.9Z"

BACKGROUND = "#FFE8C7"
RED = "#EF4A3C"
SEAM = "#C2352A"     # darker red, shows through the gap between the two halves
YELLOW = "#FFC233"   # the little doll
FACE = "#FFF4E3"
INK = "#3A1F1A"      # eyes


def face(wide):
    """Light face with two eyes. wide = surprised (the lid of the open doll)."""
    r = 0.62 if wide else 0.5
    return (f'<circle cx="12" cy="6.5" r="2.6" fill="{FACE}"/>'
            f'<circle cx="10.9" cy="6.6" r="{r}" fill="{INK}"/><circle cx="13.1" cy="6.6" r="{r}" fill="{INK}"/>')


def closed():
    return (f'<path d="{DOLL}" fill="{SEAM}"/>'
            f'<path d="{TOP}" fill="{RED}"/><path d="{BOTTOM}" fill="{RED}"/>' + face(wide=False))


def opened():
    lid = f'<g transform="translate(11.8 12.4) rotate(24 5.2 0) scale(0.78) translate(-12 -14.6)"><path d="{TOP}" fill="{RED}"/>{face(wide=True)}</g>'
    kid = f'<g transform="translate(11 21.4) scale(0.5) translate(-12 -22)"><path d="{DOLL}" fill="{YELLOW}"/>{face(wide=False)}</g>'
    base = f'<g transform="translate(12 22) scale(0.8) translate(-12 -22)"><path d="{BOTTOM}" fill="{RED}"/></g>'
    return kid + lid + base


def app_icon(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">'
            f'<rect x="10" y="10" width="100" height="100" rx="23" fill="{BACKGROUND}"/>'
            f'<g transform="translate(60 61) scale(3.5) translate(-12 -12)">{body}</g></svg>')


def mark(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">{body}</svg>'


here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "color"), exist_ok=True)
for name, body in (("closed", closed()), ("open", opened())):
    with open(os.path.join(here, "color", f"{name}.svg"), "w") as f:
        f.write(app_icon(body))
    with open(os.path.join(here, "color", f"{name}-mark.svg"), "w") as f:
        f.write(mark(body))
print("ok")
