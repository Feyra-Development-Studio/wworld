#!/usr/bin/env python3
"""Сравнение двух снимков экрана по верхней полосе.

    screens-differ.py до.png после.png [высота полосы]

Сравнивается только верхняя часть — там карта. Строка состояния меняется и
без движения героя (например, сообщением об отказе), поэтому включать её в
сравнение значит проверять не то.

Возвращает 0, если различия есть, и 1, если картинка не изменилась.
"""
import struct
import sys
import zlib


def raw(path):
    data = open(path, "rb").read()
    pos, width, idat = 8, 0, b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        if kind == b"IHDR":
            width = struct.unpack(">I", data[pos + 8:pos + 12])[0]
        elif kind == b"IDAT":
            idat += data[pos + 8:pos + 8 + length]
        pos += 12 + length
    return width, zlib.decompress(idat)


def main():
    if len(sys.argv) < 3:
        print("нужны два снимка")
        return 2

    band_rows = int(sys.argv[3]) if len(sys.argv) > 3 else 260
    width_a, a = raw(sys.argv[1])
    width_b, b = raw(sys.argv[2])

    if width_a != width_b:
        print("снимки разной ширины:", width_a, width_b)
        return 2

    # Строка развёртки в PNG — байт фильтра плюс пиксели.
    band = min(len(a), len(b), (width_a * 4 + 1) * band_rows)
    diff = sum(1 for i in range(band) if a[i] != b[i])
    print("различий в области карты:", diff)
    return 0 if diff > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
