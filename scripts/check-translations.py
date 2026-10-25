#!/usr/bin/env python3
"""Mencocokkan teks yang bisa diterjemahkan di Sources/Hachi dengan tiap Resources/<bahasa>.lproj/Localizable.strings.

Kunci terjemahan adalah teks bahasa Inggris di kode. Interpolasi Swift menjadi %@, kecuali nama di INTS
yang bertipe bilangan bulat (%lld). Keluar dengan kode 1 bila ada teks yang belum diterjemahkan atau sudah tidak dipakai.
"""
import glob
import re
import sys

INTS = {"TaskStore.doneWindowDays", "store.doneTodayCount", "TaskStore.staleDays", "every", "day", "overdue", "today", "added"}
CALL = re.compile(
    r'(String\(localized: |Text\(|Button\(|Toggle\(|Section\(|Label\(|Picker\(|TextField\(|\.help\(|'
    r'Hint\(key: "[^"]*", text: |hourPicker\()"'
)


def read_literal(src, i):
    """Membaca string literal Swift mulai setelah tanda kutip pembuka."""
    out = ""
    while True:
        c = src[i]
        if c == "\\" and src[i + 1] == "(":
            depth, j, quoted = 1, i + 2, False
            while depth:
                ch = src[j]
                if ch == '"':
                    quoted = not quoted
                elif not quoted:
                    depth += {"(": 1, ")": -1}.get(ch, 0)
                j += 1
            out += "%lld" if src[i + 2 : j - 1] in INTS else "%@"
            i = j
        elif c == "\\":
            out += src[i : i + 2]
            i += 2
        elif c == '"':
            return out
        else:
            out += c
            i += 1


def source_keys():
    keys = set()
    for path in glob.glob("Sources/Hachi/**/*.swift", recursive=True):
        src = open(path, encoding="utf-8").read()
        for match in CALL.finditer(src):
            key = read_literal(src, match.end())
            if key:
                keys.add(key)
    return keys


def strings_keys(path):
    text = open(path, encoding="utf-8").read()
    return {m.group(1) for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.MULTILINE)}


def main():
    wanted = source_keys()
    ok = True
    for path in sorted(glob.glob("Resources/*.lproj/Localizable.strings")):
        have = strings_keys(path)
        for key in sorted(wanted - have):
            print(f"{path}: belum diterjemahkan: {key}")
            ok = False
        for key in sorted(have - wanted):
            print(f"{path}: tidak dipakai lagi: {key}")
            ok = False
    print("Terjemahan lengkap." if ok else "Ada terjemahan yang perlu dibereskan.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
