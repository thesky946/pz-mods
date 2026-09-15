"""Render evenly spaced frames from a mocap reference video into one sheet."""
import sys
from pathlib import Path

import cv2


def main():
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    capture = cv2.VideoCapture(str(source))
    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    indices = [round(frame_count * index / 15) for index in range(15)]
    frames = []
    for index in indices:
        capture.set(cv2.CAP_PROP_POS_FRAMES, index)
        ok, frame = capture.read()
        if not ok:
            raise RuntimeError(f"cannot decode frame {index}")
        height, width = frame.shape[:2]
        scaled = cv2.resize(frame, (320, round(height * 320 / width)))
        cv2.putText(scaled, str(index), (10, 28), cv2.FONT_HERSHEY_SIMPLEX,
                    0.8, (0, 0, 255), 2, cv2.LINE_AA)
        frames.append(scaled)
    rows = [cv2.hconcat(frames[offset:offset + 5]) for offset in range(0, 15, 5)]
    cv2.imwrite(str(destination), cv2.vconcat(rows))


if __name__ == "__main__":
    main()
