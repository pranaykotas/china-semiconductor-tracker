#!/usr/bin/env python3
"""
Validate the tracker's YAML data before the site is built.

Catches the mistakes that otherwise fail silently: a mistyped status
("Under construction") falls through to the grey default colour and drops
out of every count; a malformed date crashes one page; a swapped lat/lon
puts a fab in the ocean; an entry with no source breaks the sourcing
standard. The deploy workflow runs this first and stops on any error.

Run from the repo root:
    python3 scripts/validate_data.py
Exit code 0 = clean (warnings may still print), 1 = errors found.
"""

import sys
from datetime import date

import yaml

# ---- Allowed values (must match the colour/badge maps in R/helpers.R) ----
FACILITY_STATUS = {"Announced", "Approved", "Under Construction", "Operational", "On Hold", "Cancelled"}
FACILITY_TYPE = {"Fab", "Memory", "Assembly & Packaging", "Compound Semiconductor", "Research Fab"}
FACILITY_CATEGORY = {"State-Backed", "Private", "JV", "Foreign-Invested"}
FUNDING_SOURCE = {"Big Fund I", "Big Fund II", "Big Fund III", "Local Govt", "Private", "Foreign", "Not disclosed"}
DESIGN_CATEGORY = {"Fabless", "State-Backed Design House", "EDA & IP Provider"}
MATERIALS_CATEGORY = {"Equipment", "Materials", "Wafer/Substrate"}

# Rough bounding box for mainland China (generous margins)
LAT_RANGE = (18.0, 54.0)
LON_RANGE = (73.0, 135.0)

errors: list[str] = []
warnings: list[str] = []


def err(label: str, msg: str) -> None:
    errors.append(f"{label}: {msg}")


def warn(label: str, msg: str) -> None:
    warnings.append(f"{label}: {msg}")


def check_date(label: str, field: str, value, required: bool = False) -> None:
    """Dates must be ISO YYYY-MM-DD strings (or YAML dates); null is OK unless required."""
    if value is None:
        if required:
            err(label, f"{field} is missing")
        return
    if isinstance(value, date):
        return
    try:
        date.fromisoformat(str(value))
    except ValueError:
        err(label, f"{field} '{value}' is not a valid YYYY-MM-DD date")


def check_coords(label: str, loc: dict | None) -> None:
    if not loc:
        err(label, "location is missing")
        return
    lat, lon = loc.get("lat"), loc.get("lon")
    if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
        err(label, f"lat/lon missing or not numeric ({lat}, {lon})")
        return
    if not (LAT_RANGE[0] <= lat <= LAT_RANGE[1] and LON_RANGE[0] <= lon <= LON_RANGE[1]):
        err(label, f"coordinates ({lat}, {lon}) fall outside mainland China — swapped lat/lon?")


def check_enum(label: str, field: str, value, allowed: set) -> None:
    if value not in allowed:
        err(label, f"{field} '{value}' not one of: {', '.join(sorted(allowed))}")


def check_sources(label: str, sources) -> None:
    if not sources:
        err(label, "no sources[] — every entry needs at least one")
        return
    for i, s in enumerate(sources):
        url = str(s.get("url") or "")
        if not url.startswith(("http://", "https://")):
            err(label, f"sources[{i}] url '{url}' is not an http(s) URL")
        if "news.google.com" in url:
            err(label, f"sources[{i}] is a Google News proxy URL — use the real article URL")
        if not s.get("title"):
            err(label, f"sources[{i}] has no title")
        check_date(label, f"sources[{i}].date", s.get("date"), required=True)


def check_capacity(label: str, cap) -> None:
    """A capacity block needs exactly one kind of figure, positive, plus an as_of."""
    if not cap:
        return
    kinds = [k for k in ("wafers_per_month", "units_per_month", "amount") if cap.get(k) is not None]
    if len(kinds) != 1:
        err(label, "capacity needs exactly one of wafers_per_month, units_per_month, or amount+unit")
        return
    v = cap[kinds[0]]
    if not isinstance(v, (int, float)) or v <= 0:
        err(label, f"capacity.{kinds[0]} '{v}' must be a positive number")
    if kinds[0] == "amount" and not cap.get("unit"):
        err(label, "capacity.amount given without capacity.unit")
    if cap.get("as_of") is None:
        warn(label, "capacity has no as_of date")
    if cap.get("basis") not in ("installed", "planned"):
        err(label, f"capacity.basis '{cap.get('basis')}' must be 'installed' or 'planned'")


def check_trajectory(label: str, entries, field: str, name: str) -> None:
    """Dated trajectory lists: integer years, non-empty text, chronological."""
    years = []
    for i, t in enumerate(entries or []):
        if not isinstance(t.get("year"), int):
            err(label, f"{name}[{i}].year '{t.get('year')}' must be an integer year")
        else:
            years.append(t["year"])
        if not t.get(field):
            err(label, f"{name}[{i}] has no {field}")
    if years != sorted(years):
        err(label, f"{name} is not in chronological order")


def check_entity_list(label: str, el) -> None:
    el = el or {}
    if el.get("status") is True:
        if not el.get("list"):
            err(label, "entity_list.status is true but entity_list.list is empty")
        check_date(label, "entity_list.date_added", el.get("date_added"), required=True)


def check_ids(entries: list, file_label: str) -> None:
    ids = [e.get("id") for e in entries]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        err(file_label, f"duplicate id(s): {', '.join(sorted(map(str, dupes)))}")
    for i in ids:
        if not i or not str(i).replace("-", "").isalnum() or str(i) != str(i).lower():
            err(file_label, f"id '{i}' must be lowercase letters, digits, and hyphens")


def validate_facilities(path: str = "data/facilities.yml") -> int:
    entries = yaml.safe_load(open(path, encoding="utf-8"))["facilities"]
    check_ids(entries, path)
    for f in entries:
        label = f"facilities/{f.get('id')}"
        for field in ("name_en", "company_en"):
            if not f.get(field):
                err(label, f"{field} is missing")
        check_enum(label, "status", f.get("status"), FACILITY_STATUS)
        check_enum(label, "type", f.get("type"), FACILITY_TYPE)
        check_enum(label, "category", f.get("category"), FACILITY_CATEGORY)
        check_coords(label, f.get("location"))
        check_sources(label, f.get("sources"))
        check_entity_list(label, f.get("entity_list"))

        inv = f.get("investment") or {}
        check_enum(label, "investment.source", inv.get("source", "Not disclosed"), FUNDING_SOURCE)
        for k in ("total_rmb_100m", "total_usd_million"):
            v = inv.get(k)
            if v is not None and (not isinstance(v, (int, float)) or v < 0):
                err(label, f"investment.{k} '{v}' must be a non-negative number")

        for k, v in (f.get("dates") or {}).items():
            check_date(label, f"dates.{k}", v)
        for i, m in enumerate(f.get("milestones") or []):
            check_date(label, f"milestones[{i}].date", m.get("date"), required=True)
            if not m.get("event"):
                err(label, f"milestones[{i}] has no event text")
        check_trajectory(label, f.get("node_trajectory"), "node", "node_trajectory")
        check_trajectory(label, f.get("packaging_trajectory"), "technology", "packaging_trajectory")
        if f.get("packaging_trajectory") and f.get("type") != "Assembly & Packaging":
            err(label, "packaging_trajectory is only for Assembly & Packaging facilities")

        check_date(label, "last_verified", f.get("last_verified"))
        check_capacity(label, f.get("capacity"))

        for k in ("technology_difficulty", "capital_intensity", "foreign_dependence"):
            v = (f.get("complexity") or {}).get(k)
            if v is not None and not (1 <= v <= 5):
                err(label, f"complexity.{k} '{v}' must be between 1 and 5")

        if f.get("status") == "Cancelled" and not f.get("milestones"):
            warn(label, "cancelled project has no milestones — its timeline bar has no end date")
        if not f.get("name_zh"):
            warn(label, "name_zh not yet verified")
    return len(entries)


def validate_design(path: str = "data/design.yml") -> int:
    entries = yaml.safe_load(open(path, encoding="utf-8"))["design_firms"]
    check_ids(entries, path)
    for f in entries:
        label = f"design/{f.get('id')}"
        if not f.get("name_en"):
            err(label, "name_en is missing")
        check_enum(label, "category", f.get("category"), DESIGN_CATEGORY)
        check_coords(label, f.get("location"))
        check_sources(label, f.get("sources"))
        check_entity_list(label, f.get("entity_list"))
        for k, v in (f.get("design_score") or {}).items():
            if v is not None and not (1 <= v <= 5):
                err(label, f"design_score.{k} '{v}' must be between 1 and 5")
    return len(entries)


def validate_materials(path: str = "data/materials.yml") -> int:
    entries = yaml.safe_load(open(path, encoding="utf-8"))["materials_firms"]
    check_ids(entries, path)
    for f in entries:
        label = f"materials/{f.get('id')}"
        if not f.get("name_en"):
            err(label, "name_en is missing")
        if not f.get("segment"):
            err(label, "segment is missing")
        check_enum(label, "category", f.get("category"), MATERIALS_CATEGORY)
        check_coords(label, f.get("hq"))
        check_sources(label, f.get("sources"))
        check_entity_list(label, f.get("entity_list"))
        check_trajectory(label, f.get("capability_trajectory"), "capability", "capability_trajectory")
        check_capacity(label, f.get("capacity"))
        check_date(label, "last_verified", f.get("last_verified"))
        for i, m in enumerate(f.get("manufacturing_sites") or []):
            for k in ("name", "city", "what"):
                if not m.get(k):
                    err(label, f"manufacturing_sites[{i}] has no {k}")
    return len(entries)


def main() -> None:
    counts = {
        "facilities": validate_facilities(),
        "design firms": validate_design(),
        "equipment/materials firms": validate_materials(),
    }
    print("Checked " + ", ".join(f"{n} {k}" for k, n in counts.items()) + ".")

    for w in warnings:
        print(f"  warning  {w}")
    for e in errors:
        print(f"  ERROR    {e}")

    if errors:
        print(f"\n{len(errors)} error(s) found. Fix them before deploying.")
        sys.exit(1)
    print("No errors.")


if __name__ == "__main__":
    main()
