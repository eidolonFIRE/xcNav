"""Generate assets/geoid/egm96_0.5deg.bin from GeographicLib's EGM96 15-minute geoid grid.

Source: https://sourceforge.net/projects/geographiclib/files/geoids-distrib/egm96-15.tar.bz2
Extract it and pass the path to egm96-15.pgm:

    python scripts/gen_geoid_grid.py path/to/egm96-15.pgm [step_degrees]

Output layout (read by lib/models/geoid.dart):
    int16 little-endian, centimeters, geoid height N above the WGS84 ellipsoid.
    rows = 180/step + 1, from 90N down to 90S.
    cols = 360/step, from 0E eastward (wraps at 360).
"""

import struct
import sys
from pathlib import Path


def read_pgm(path):
    data = Path(path).read_bytes()
    pos = 0
    tokens = []
    offset = scale = None
    while len(tokens) < 4:
        end = data.index(b"\n", pos)
        line = data[pos:end].decode("ascii")
        pos = end + 1
        if line.startswith("#"):
            parts = line[1:].split()
            if parts and parts[0] == "Offset":
                offset = float(parts[1])
            elif parts and parts[0] == "Scale":
                scale = float(parts[1])
            continue
        tokens.extend(line.split())
    width, height = int(tokens[1]), int(tokens[2])
    raw = struct.unpack(f">{width * height}H", data[pos : pos + width * height * 2])
    rows = [[offset + scale * raw[r * width + c] for c in range(width)] for r in range(height)]
    return rows, width, height


def bilinear(grid, cols, step, lat, lon):
    y = (90 - lat) / step
    x = (lon % 360) / step
    r0 = min(int(y), len(grid) - 2)
    c0 = int(x) % cols
    c1 = (c0 + 1) % cols
    fy = y - r0
    fx = x - int(x)
    top = grid[r0][c0] * (1 - fx) + grid[r0][c1] * fx
    bot = grid[r0 + 1][c0] * (1 - fx) + grid[r0 + 1][c1] * fx
    return top * (1 - fy) + bot * fy


def main():
    src = sys.argv[1]
    step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
    full, width, height = read_pgm(src)
    src_step = 360 / width
    stride = round(step / src_step)

    cols = round(360 / step)
    rows = round(180 / step) + 1
    grid = [[full[r * stride][c * stride] for c in range(cols)] for r in range(rows)]

    # Error vs. the full-resolution grid at every source point
    max_err = 0.0
    sum_sq = 0.0
    n = 0
    for r in range(height):
        lat = 90 - r * src_step
        for c in range(width):
            lon = c * src_step
            err = abs(bilinear(grid, cols, step, lat, lon) - full[r][c])
            max_err = max(max_err, err)
            sum_sq += err * err
            n += 1
    print(f"{cols}x{rows} grid, max err {max_err:.2f} m, rms err {(sum_sq / n) ** 0.5:.3f} m")

    out = Path(__file__).resolve().parent.parent / "assets" / "geoid" / f"egm96_{step:g}deg.bin"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(b"".join(struct.pack("<h", round(v * 100)) for row in grid for v in row))
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
