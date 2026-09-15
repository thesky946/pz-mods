"""Bake a hand-keyed spinning-kick performance onto PZ's Bob skeleton.

The game loads the produced .X clip. This tool is authoring-only and is not
included in the Workshop build.
"""
import math
import re
import sys
from pathlib import Path


def quat(axis, degrees):
    x, y, z = axis
    length = math.sqrt(x * x + y * y + z * z)
    x, y, z = x / length, y / length, z / length
    half = math.radians(degrees) / 2.0
    return math.cos(half), x * math.sin(half), y * math.sin(half), z * math.sin(half)


def mul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (
        aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
    )


# Twenty-one source keys: guard, wind-up, full turn, high contact, recovery.
# Values are authored local-bone deltas, not global transforms.
KEYS = {
    "Bip01": [(0, 0, 0), (0, 0, 0), (0, 0, 4), (0, 0, 15), (0, 0, 38), (0, 0, 72), (0, 0, 118), (0, 0, 166), (0, 0, 214), (0, 0, 256), (0, 0, 292), (0, 0, 320), (0, 0, 338), (0, 0, 350), (0, 0, 358), (0, 0, 360), (0, 0, 360), (0, 0, 360), (0, 0, 360), (0, 0, 360), (0, 0, 360)],
    "Bip01_R_Thigh": [(1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 6), (1, 0, 16), (1, 0, 32), (1, 0, 50), (1, 0, 68), (1, 0, 82), (1, 0, 90), (1, 0, 86), (1, 0, 72), (1, 0, 54), (1, 0, 34), (1, 0, 18), (1, 0, 8), (1, 0, 3), (1, 0, 0), (1, 0, 0), (1, 0, 0)],
    "Bip01_R_Calf": [(1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, -8), (1, 0, -20), (1, 0, -38), (1, 0, -54), (1, 0, -64), (1, 0, -70), (1, 0, -72), (1, 0, -64), (1, 0, -52), (1, 0, -36), (1, 0, -20), (1, 0, -10), (1, 0, -4), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0)],
    "Bip01_R_Foot": [(1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 8), (1, 0, 18), (1, 0, 28), (1, 0, 34), (1, 0, 38), (1, 0, 42), (1, 0, 45), (1, 0, 38), (1, 0, 28), (1, 0, 18), (1, 0, 10), (1, 0, 4), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0), (1, 0, 0)],
    "Bip01_Spine": [(0, 0, 0), (0, 0, 0), (0, 0, -2), (0, 0, -8), (0, 0, -18), (0, 0, -28), (0, 0, -32), (0, 0, -24), (0, 0, -12), (0, 0, 4), (0, 0, 12), (0, 0, 10), (0, 0, 6), (0, 0, 2), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0)],
}

AXES = {
    "Bip01": (0, 0, 1),
    "Bip01_R_Thigh": (1, 0, 0),
    "Bip01_R_Calf": (1, 0, 0),
    "Bip01_R_Foot": (1, 0, 0),
    "Bip01_Spine": (0, 0, 1),
}


def edit_bone(text, bone, deltas, axis):
    block = re.compile(r"(Animation\s*\{\s*\{\s*" + re.escape(bone) + r"\s*\}.*?AnimationKey R\s*\{\s*0;\s*21;)(.*?)(\s*\}\s*\})", re.S)
    match = block.search(text)
    if not match:
        raise ValueError("rotation track not found: " + bone)
    key = re.compile(r"(\d+;4;)([-0-9.eE]+),([-0-9.eE]+),([-0-9.eE]+),([-0-9.eE]+)(;;[,;])")
    index = 0

    def replace(m):
        nonlocal index
        if index >= len(deltas):
            return m.group(0)
        source = tuple(float(m.group(i)) for i in range(2, 6))
        degrees = deltas[index][2]
        index += 1
        result = mul(source, quat(axis, degrees))
        return m.group(1) + ",".join(f"{value:.6f}" for value in result) + m.group(6)

    body = key.sub(replace, match.group(2))
    if index != 21:
        raise ValueError(f"unexpected key count for {bone}: {index}")
    return text[:match.start(2)] + body + text[match.end(2):]


def main():
    source, destination = map(Path, sys.argv[1:3])
    text = source.read_text(encoding="utf-8")
    for bone, values in KEYS.items():
        text = edit_bone(text, bone, values, AXES[bone])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
