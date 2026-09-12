#!/usr/bin/env python3
"""
Regenerate PhoneNumberMetadata.json from a PINNED libphonenumber release.

    ./Scripts/generate-metadata.py                 # uses PINNED_RELEASE below
    ./Scripts/generate-metadata.py v9.0.40         # bump

Google reissues this metadata roughly every two weeks. Stale metadata fails in
the WORST direction: a newly-allocated mobile block reads as INVALID, silently.
So this script is the product — re-run it, commit the JSON, cut a patch release.

The generated JSON is COMMITTED so that a bare clone builds with no network.
"""
import json, re, sys, urllib.request, xml.etree.ElementTree as ET
from datetime import date, timezone, datetime
from pathlib import Path

PINNED_RELEASE = "v9.0.39"
URL = "https://raw.githubusercontent.com/google/libphonenumber/{tag}/resources/PhoneNumberMetadata.xml"
OUT = Path(__file__).resolve().parent.parent / "Sources/PhoneValidator/Resources/PhoneNumberMetadata.json"

# The order matters: the first type whose pattern matches wins when a number is
# ambiguous, and fixedLine/mobile overlap in many territories.
NON_GEO_ID = "001"

TYPES = ["fixedLine", "mobile", "pager", "tollFree", "premiumRate",
         "sharedCost", "personalNumber", "voip", "uan", "voicemail"]


def squash(pattern):
    """Strip the pretty-printing whitespace out of a pattern.

    THE trap in this file. The XML is indented for humans, so a pattern reads
    `[1-357-9]\\d{9}| [18]\\d{8}` — that space after the pipe is formatting, not
    regex. Leave it in and every alternation branch after the first stops
    matching, which looks like "this country is broken" rather than a parse bug.
    """
    return re.sub(r"\s+", "", pattern or "")


def lengths(el):
    """possibleLengths national= as written: '9,10' or '[4-6]' or '7,9,10'."""
    node = el.find("possibleLengths")
    if node is None:
        return None
    return node.get("national") or None


def desc(el):
    """One number type -> {p: pattern, l: lengths, e: example}, or None."""
    if el is None:
        return None
    pattern = squash(el.findtext("nationalNumberPattern"))
    if not pattern:
        return None
    out = {"p": pattern}
    lens = lengths(el)
    if lens:
        out["l"] = lens
    example = (el.findtext("exampleNumber") or "").strip()
    if example:
        out["e"] = example
    return out


def formats(territory):
    """availableFormats -> the display rules, in document order."""
    parent = territory.find("availableFormats")
    if parent is None:
        return []
    out = []
    for f in parent.findall("numberFormat"):
        rule = {"p": squash(f.get("pattern")), "f": (f.findtext("format") or "").strip()}
        leading = [squash(x.text) for x in f.findall("leadingDigits") if (x.text or "").strip()]
        if leading:
            rule["ld"] = leading
        if f.get("nationalPrefixFormattingRule"):
            rule["npf"] = f.get("nationalPrefixFormattingRule").strip()
        if f.get("carrierCodeFormattingRule"):
            rule["ccf"] = f.get("carrierCodeFormattingRule").strip()
        if f.get("nationalPrefixOptionalWhenFormatting") == "true":
            rule["npo"] = True
        if rule["f"]:
            out.append(rule)
    return out


def verify(territories, non_geo):
    """Prove the patterns survived generation, using the metadata's own examples.

    Every type carries an exampleNumber that its own pattern must fully match.
    That is free ground truth, and it is what catches the whitespace trap: leave
    the pretty-printing in and the pass rate collapses instead of the file
    merely looking fine.
    """
    checked = failed = 0
    for name, entry in list(territories.items()) + [("+" + k, v) for k, v in non_geo.items()]:
        for kind, d in (entry.get("t") or {}).items():
            example = d.get("e")
            if not example:
                continue
            checked += 1
            if not re.fullmatch(d["p"], example):
                failed += 1
                if failed <= 5:
                    print(f"    MISMATCH {name}/{kind}: {example} !~ {d['p'][:48]}")
    rate = 100.0 * (checked - failed) / checked if checked else 0.0
    print(f"  verified {checked - failed}/{checked} example numbers against their "
          f"own patterns ({rate:.2f}%)")
    if failed:
        raise SystemExit(f"REFUSING to write: {failed} patterns do not match their own example")


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else PINNED_RELEASE
    url = URL.format(tag=tag)
    print(f"fetching {tag} …")
    req = urllib.request.Request(url, headers={"User-Agent": "swift-phone-validator/generator"})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
    print(f"  {len(raw):,} bytes of XML")

    root = ET.fromstring(raw)
    territories, by_code, non_geo = {}, {}, {}

    for t in root.findall(".//territory"):
        rid = t.get("id")
        code = t.get("countryCode")
        if not rid or not code:
            continue

        entry = {"c": code}
        if t.get("mainCountryForCode") == "true":
            entry["main"] = True
        for attr, key in (("nationalPrefix", "np"),
                          ("nationalPrefixForParsing", "npp"),
                          ("nationalPrefixTransformRule", "npt"),
                          ("internationalPrefix", "ip"),
                          ("preferredInternationalPrefix", "pip"),
                          ("leadingDigits", "ld")):
            value = t.get(attr)
            if value:
                entry[key] = squash(value) if key in ("npp", "ld") else value.strip()
        if t.get("mobileNumberPortableRegion") == "true":
            entry["mnp"] = True

        general = desc(t.find("generalDesc"))
        if general:
            entry["gen"] = general["p"]

        types = {}
        for name in TYPES:
            d = desc(t.find(name))
            if d:
                types[name] = d
        if types:
            entry["t"] = types

        fmts = formats(t)
        if fmts:
            entry["f"] = fmts

        # id="001" is NOT a region — it is libphonenumber's marker for the nine
        # non-geographical calling codes (+800 freephone, +808 shared cost,
        # +870/+881 satellite, +878/+882/+883 international networks, +888,
        # +979). They all carry the same id, so keying on it keeps ONE of nine
        # and silently drops the rest. They key on the calling code instead.
        if rid == NON_GEO_ID:
            non_geo[code] = entry
            continue

        territories[rid] = entry
        by_code.setdefault(code, [])
        # the main country for a calling code must be tried first
        if entry.get("main"):
            by_code[code].insert(0, rid)
        else:
            by_code[code].append(rid)

    payload = {
        "source": "libphonenumber",
        "sourceRelease": tag,
        "sourceURL": url,
        "sourceLicense": "Apache-2.0",
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "regions": territories,
        "nonGeographical": non_geo,
        "callingCodes": by_code,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    # separators matter: the default ', ' / ': ' costs ~15% for nothing
    text = json.dumps(payload, separators=(",", ":"), sort_keys=True, ensure_ascii=False)
    OUT.write_text(text, encoding="utf-8")
    print(f"  {len(territories)} regions, {len(non_geo)} non-geographical codes, "
          f"{len(by_code)} calling codes")
    verify(territories, non_geo)
    print(f"wrote {OUT.relative_to(OUT.parents[3])} — {OUT.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
