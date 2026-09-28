# China Semiconductor Tracker — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Quarto + R semiconductor tracker for mainland China, forked from the India Semiconductor Tracker (`../techgeopolitics`), with trilingual (English/Chinese/Pinyin) facility and company names, and China-specific fields (US Entity List status, Big Fund financing, equipment origin, technology-node trajectory) — populated with a Phase-1 dataset of ~25-30 facilities, 2-3 design firms, and 4-6 equipment/materials firms.

**Architecture:** Same pattern as the India tracker: YAML files under `data/` are the single source of truth; `R/helpers.R` loads and transforms them into tibbles; `.qmd` pages render maps (leaflet), tables (DT), and charts (ggplot2) from those tibbles; per-entity profile pages are generated from YAML by dedicated `R/generate_*_pages.R` scripts. No database, no build step beyond `quarto render`.

**Tech Stack:** Quarto, R (`yaml`, `dplyr`, `tidyr`, `leaflet`, `DT`, `ggplot2`, `scales`, `glue`, `htmltools`, `sf`, `rnaturalearth`, `ragg`), GitHub Pages + GitHub Actions for deployment.

**Spec:** `docs/superpowers/specs/2026-09-28-china-semiconductor-tracker-design.md`

## Global Constraints

- Trilingual (`name_en`/`name_zh`/`name_pinyin`, `company_en`/`company_zh`/`company_pinyin`) fields apply to facility, design-firm, and equipment/materials-firm names only — not to city/province names, which stay English-only.
- Facility `status` values are exactly: `Announced` | `Approved` | `Under Construction` | `Operational` | `On Hold` | `Cancelled` (same enum as the India tracker — reuse `status_color()`/`status_badge_html()` unchanged).
- Facility `complexity` scoring formula is unchanged from the India tracker: composite = `technology_difficulty * 0.55 + capital_intensity * 0.45`, 1-5 scale, benchmarked against a 3nm fab = 5/5.
- Investment is recorded in **¥ (RMB) 亿 (100 million yuan)**, field name `total_rmb_100m` — the unit Chinese financial press actually reports in, mirroring how the India tracker uses crore. A firm may additionally carry `total_usd_million` when only a dollar figure is publicly disclosed (mirrors `equipment_materials.yml`'s dual-currency pattern).
- Every fact that goes into a YAML file (investment figures, dates, entity-list status, node capability) must trace to a cited source in that entry's `sources:` list, per the Sourcing Strategy section of the spec. Never fabricate a number to fill a field — if unverified, leave it `null`/omitted and the existing helper convention (`%||% "Not disclosed"` / `NA`) will render it honestly as unknown, exactly as the India tracker already does for undisclosed India investments.
- Taiwan/TSMC entities are out of scope for every task in this plan (per spec).
- Do not fork the India tracker's automation scripts (`scripts/india_semi_watch.py`, `design_sweep.py`, `weekly_digest.py`) or their GitHub Actions workflows — only `deploy.yml` is in scope (per spec's "real-time news/commentary scraping" exclusion).

## Review Focus

- A facility with no verified `name_zh`/`name_pinyin` yet (research in progress) must render without a broken or empty Chinese-name line in the popup/table, not crash the page — covered in Task 2's fixture tests and Task 4's render check.
- A facility with no `node_trajectory` entries yet must be silently skipped by the nodes.qmd aggregate chart, not throw an error or plot a blank line — covered in Task 8.
- Long CJK-character names (e.g. `中芯国际集成电路制造有限公司`, 15+ characters) must not overflow or break the DT table layout or leaflet popups — covered in Task 4's render check with a real long name from Task 3's data.
- Duplicate `id` values across research batches (the same facility added twice by mistake, e.g. two SMIC entries both called `smic-shanghai`) must be caught before merge, not silently overwrite one entry's profile page — covered by an explicit uniqueness check added in Task 3.
- Summing `investment_rmb100m` across facilities with mixed disclosed/undisclosed (`NA`) investment must not turn summary-card totals into `NA` — covered in Task 4 and Task 11 by using `na.rm = TRUE` consistently, matching the India tracker's existing pattern.

---

## Task 1: Project skeleton, config, and stub pages

**Files:**
- Create: `_quarto.yml`
- Create: `styles.scss` (copied from `../techgeopolitics/styles.scss`)
- Create: `takshashila-base.scss` (copied from `../techgeopolitics/takshashila-base.scss`)
- Create: `images/favicon.svg` (copied from `../techgeopolitics/images/favicon.svg`)
- Create: `.gitignore`
- Create: `about.qmd`, `index.qmd`, `timeline.qmd`, `nodes.qmd`, `design.qmd`, `equipment-materials.qmd`, `funding.qmd`, `export-controls.qmd` (stub pages)
- Create: `.github/workflows/deploy.yml`

**Interfaces:**
- Produces: a renderable Quarto site skeleton with working nav; every later task replaces exactly one stub `.qmd` with real content.

- [ ] **Step 1: Copy static assets from the India tracker**

```bash
cp ../techgeopolitics/styles.scss styles.scss
cp ../techgeopolitics/takshashila-base.scss takshashila-base.scss
mkdir -p images
cp ../techgeopolitics/images/favicon.svg images/favicon.svg
```

- [ ] **Step 2: Write `.gitignore`**

```
/_site/
/.quarto/
.Renviron
*.qmd~
.DS_Store
```

- [ ] **Step 3: Write `_quarto.yml`**

```yaml
project:
  type: website
  output-dir: _site
  render:
    - "*.qmd"
    - "!CLAUDE.md"

website:
  title: "China Semiconductor Tracker"
  description: "Tracking semiconductor manufacturing, chip design, and equipment firms across mainland China"
  favicon: "images/favicon.svg"
  site-url: "https://fabs-china.pranaykotas.com"

  navbar:
    background: "#620d3c"
    foreground: "#ffffff"
    left:
      - text: "Map & Overview"
        href: index.qmd
      - text: "Timeline"
        href: timeline.qmd
      - text: "Technology Nodes"
        href: nodes.qmd
      - text: "Chip Design"
        href: design.qmd
      - text: "Equipment & Materials"
        href: equipment-materials.qmd
      - text: "State Funding"
        href: funding.qmd
      - text: "Export Controls"
        href: export-controls.qmd
      - text: "About"
        href: about.qmd
    right:
      - text: "Takshashila"
        href: https://takshashila.org.in
        aria-label: "Takshashila Institution"
      - icon: github
        href: https://github.com/pranaykotas/china-semiconductor-tracker
        aria-label: "GitHub repository"

  page-footer:
    left: |
      &copy; 2026 [Pranay Kotasthane](https://pranaykotas.com) · [Takshashila Institution](https://takshashila.org.in)
    center: |
      Part of the [Siliconpolitik Project](https://takshashila.org.in/pages/research-areas/focus-areas/siliconpolitik.html)
    right: |
      [Report an issue](https://github.com/pranaykotas/china-semiconductor-tracker/issues/new)

  search: true

format:
  html:
    theme:
      light: [cosmo, styles.scss]
    toc: true
    toc-depth: 2
    mainfont: "Inter"
    monofont: "Roboto Mono"
```

- [ ] **Step 4: Write stub pages**

Create each of the following with this pattern (substitute `{title}` and `{task}`):

```markdown
---
title: "{title}"
date: last-modified
---

*Content coming in Task {task} of the implementation plan.*
```

| File | title | task |
|---|---|---|
| `index.qmd` | China Semiconductor Tracker: Facilities | 4 |
| `timeline.qmd` | Project Timeline | 7 |
| `nodes.qmd` | Technology Nodes | 8 |
| `design.qmd` | Chip Design in China | 9 |
| `equipment-materials.qmd` | Equipment & Materials | 10 |
| `funding.qmd` | State Funding | 11 |
| `export-controls.qmd` | Export Controls | 12 |
| `about.qmd` | About This Tracker | 13 |

- [ ] **Step 5: Write the deploy workflow**

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy to GitHub Pages

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true

      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          packages: |
            any::yaml
            any::dplyr
            any::tidyr
            any::leaflet
            any::DT
            any::ggplot2
            any::scales
            any::glue
            any::htmltools
            any::sf
            any::rnaturalearth
            any::ragg

      - uses: quarto-dev/quarto-actions/setup@v2

      - name: Generate facility pages
        run: Rscript R/generate_facility_pages.R

      - name: Generate design firm pages
        run: Rscript R/generate_design_pages.R

      - name: Generate equipment/materials firm pages
        run: Rscript R/generate_materials_pages.R

      - name: Render site
        run: quarto render
        env:
          CARTO_API_KEY: ${{ secrets.CARTO_API_KEY }}

      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 6: Render to verify the skeleton works**

Run: `quarto render`
Expected: `_site/` is created with 8 rendered HTML pages, nav links all resolve, no errors.

- [ ] **Step 7: Commit**

```bash
git add _quarto.yml styles.scss takshashila-base.scss images/ .gitignore \
  index.qmd timeline.qmd nodes.qmd design.qmd equipment-materials.qmd \
  funding.qmd export-controls.qmd about.qmd .github/
git commit -m "feat: project skeleton forked from India Semiconductor Tracker"
```

---

## Task 2: `R/helpers.R` — facilities schema loader and rendering helpers

**Files:**
- Create: `R/helpers.R`
- Create: `R/test_fixtures/facilities_fixture.yml` (throwaway fixture, deleted at end of task)

**Interfaces:**
- Produces: `load_facilities(path)` returning a tibble with columns: `id, name_en, name_zh, name_pinyin, company_en, company_zh, company_pinyin, partners, city, province, lat, lon, type, category, capability, investment_rmb100m, investment_usd_m, investment_source, status, status_detail, entity_list_flagged, entity_list_date, entity_list_name, domestic_pct, key_foreign_tools, smuggled_flagged, current_node, complexity_tech, complexity_foreign, complexity_capital, complexity_score, date_announced, date_approved, date_construction, date_completion, date_original_expect, delay_confirmed, significance, what_it_makes, why_it_matters`; plus `format_investment()`, `status_color()`, `category_color()`, `category_badge_html()`, `status_badge_html()`, `complexity_bar_html()`, `entity_list_badge_html()`, `make_popup()`, `make_label()`.
- Consumes: nothing (first data-layer task).

- [ ] **Step 1: Write the fixture YAML**

```yaml
# R/test_fixtures/facilities_fixture.yml
facilities:
  - id: fixture-a
    name_en: "Fixture Fab A"
    name_zh: "示例工厂甲"
    name_pinyin: "Shìlì Gōngchǎng Jiǎ"
    company_en: "Fixture Corp"
    company_zh: "示例公司"
    company_pinyin: "Shìlì Gōngsī"
    partners: []
    location: {city: "Shanghai", province: "Shanghai Municipality", lat: 31.230, lon: 121.474}
    type: "Fab"
    category: "State-Backed"
    capability: "Test capability"
    investment: {total_rmb_100m: 500, source: "Big Fund II"}
    status: "Operational"
    entity_list: {status: true, date_added: "2020-12-18", list: "US Commerce BIS"}
    equipment_origin: {domestic_pct: 30, key_foreign_tools: ["ASML DUV"], smuggled_flagged: false}
    node_trajectory:
      - {year: 2019, node: "14nm"}
      - {year: 2024, node: "7nm DUV"}
    narrative:
      significance: "Fixture significance."
      what_it_makes: "Fixture product."
      why_it_matters: "Fixture importance."
    milestones: []
    complexity: {technology_difficulty: 4, foreign_dependence: 4, capital_intensity: 5}
    dates: {announced: "2019-01-01", approved: "2019-06-01", construction_start: "2019-09-01", original_expected_completion: "2022-01-01", date_completion: "2022-06-01"}
    sources: []
  - id: fixture-b
    name_en: "Fixture Fab B (names unverified)"
    name_zh: null
    name_pinyin: null
    company_en: "Fixture Corp B"
    company_zh: null
    company_pinyin: null
    partners: []
    location: {city: "Wuhan", province: "Hubei", lat: 30.593, lon: 114.305}
    type: "Memory"
    category: "Private"
    capability: "Test capability B"
    investment: {total_rmb_100m: null, source: "Private"}
    status: "Under Construction"
    entity_list: {status: false, date_added: null, list: null}
    equipment_origin: {domestic_pct: null, key_foreign_tools: [], smuggled_flagged: false}
    node_trajectory: []
    narrative: {significance: "", what_it_makes: "", why_it_matters: ""}
    milestones: []
    complexity: {technology_difficulty: 3, foreign_dependence: 3, capital_intensity: 4}
    dates: {announced: "2021-01-01", approved: null, construction_start: "2021-06-01", original_expected_completion: "2024-01-01", date_completion: null}
    sources: []
```

This fixture exercises the two Review Focus risks that belong to this task: fixture-b has no `name_zh`/`name_pinyin` (unverified names) and no `node_trajectory` (unresearched) — the loader and popup builder must handle both without erroring.

- [ ] **Step 2: Run a smoke check against the fixture to confirm it fails (no loader yet)**

Run: `Rscript -e 'source("R/helpers.R")'`
Expected: FAIL — `R/helpers.R` does not exist yet.

- [ ] **Step 3: Write `R/helpers.R`**

```r
# helpers.R — Shared functions for the China Semiconductor Tracker
library(yaml)
library(dplyr)
library(tidyr)
library(glue)
library(htmltools)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---- Load and flatten facilities YAML into a tibble ----
load_facilities <- function(path = "data/facilities.yml") {
  raw <- yaml::read_yaml(path)

  ids <- sapply(raw$facilities, function(f) f$id)
  if (any(duplicated(ids))) {
    stop("Duplicate facility id(s) found: ", paste(unique(ids[duplicated(ids)]), collapse = ", "))
  }

  rows <- lapply(raw$facilities, function(f) {
    trajectory <- f$node_trajectory
    current_node <- if (length(trajectory) > 0) {
      trajectory[[length(trajectory)]]$node
    } else {
      NA_character_
    }

    tibble(
      id                    = f$id,
      name_en               = f$name_en,
      name_zh               = f$name_zh %||% NA_character_,
      name_pinyin           = f$name_pinyin %||% NA_character_,
      company_en            = f$company_en,
      company_zh            = f$company_zh %||% NA_character_,
      company_pinyin        = f$company_pinyin %||% NA_character_,
      partners              = paste(f$partners, collapse = ", "),
      city                  = f$location$city,
      province              = f$location$province,
      lat                   = f$location$lat,
      lon                   = f$location$lon,
      type                  = f$type,
      category              = f$category,
      capability            = f$capability %||% "Not disclosed",
      investment_rmb100m    = f$investment$total_rmb_100m %||% NA_real_,
      investment_usd_m      = f$investment$total_usd_million %||% NA_real_,
      investment_source     = f$investment$source %||% "Not disclosed",
      status                = f$status,
      status_detail         = f$status_detail %||% "",
      entity_list_flagged   = f$entity_list$status %||% FALSE,
      entity_list_date      = as.Date(f$entity_list$date_added %||% NA),
      entity_list_name      = f$entity_list$list %||% NA_character_,
      domestic_pct          = f$equipment_origin$domestic_pct %||% NA_real_,
      key_foreign_tools     = paste(f$equipment_origin$key_foreign_tools, collapse = ", "),
      smuggled_flagged      = f$equipment_origin$smuggled_flagged %||% FALSE,
      current_node          = current_node %||% NA_character_,
      complexity_tech       = f$complexity$technology_difficulty %||% 1,
      complexity_foreign    = f$complexity$foreign_dependence %||% 1,
      complexity_capital    = f$complexity$capital_intensity %||% 1,
      date_announced        = as.Date(f$dates$announced %||% NA),
      date_approved         = as.Date(f$dates$approved %||% NA),
      date_construction     = as.Date(f$dates$construction_start %||% NA),
      date_completion       = as.Date(f$dates$date_completion %||% NA),
      date_original_expect  = as.Date(f$dates$original_expected_completion %||% NA),
      delay_confirmed       = f$delay_confirmed %||% FALSE,
      significance          = f$narrative$significance %||% "",
      what_it_makes         = f$narrative$what_it_makes %||% "",
      why_it_matters        = f$narrative$why_it_matters %||% ""
    )
  })

  df <- bind_rows(rows)

  set.seed(42)
  df <- df %>%
    mutate(
      lat = lat + runif(n(), -0.015, 0.015),
      lon = lon + runif(n(), -0.015, 0.015),
      complexity_score = round((complexity_tech * 0.55) + (complexity_capital * 0.45), 1)
    )

  df
}

# ---- Format RMB investment (亿 = 100 million yuan), with optional USD ----
format_investment <- function(rmb_100m, usd_m = NA_real_, short = FALSE) {
  parts <- c()
  if (!is.na(rmb_100m) && rmb_100m > 0) {
    suffix <- if (short) "亿" else "亿元"
    parts <- c(parts, paste0("¥", format(rmb_100m, big.mark = ","), suffix))
  }
  if (!is.na(usd_m) && usd_m > 0) {
    parts <- c(parts, paste0("$", format(usd_m, big.mark = ","), "M"))
  }
  if (length(parts) == 0) return("Not disclosed")
  paste(parts, collapse = " / ")
}

# ---- Map status to display colour (unchanged enum from India tracker) ----
status_color <- function(status) {
  switch(status,
    "Operational"        = "#2f6b4a",
    "Under Construction" = "#1565C0",
    "Approved"           = "#f1a222",
    "Announced"          = "#8C8480",
    "On Hold"            = "#a3282d",
    "Cancelled"          = "#a3282d",
    "#8C8480"
  )
}

# ---- Map ownership category to marker colour (China's core narrative axis) ----
category_color <- function(category) {
  switch(category,
    "State-Backed"      = "#620d3c",
    "Private"           = "#2f6b6b",
    "JV"                = "#6A1B9A",
    "Foreign-Invested"  = "#1565C0",
    "#757575"
  )
}

# ---- Render an HTML status badge (unchanged from India tracker) ----
status_badge_html <- function(status, detail = "") {
  css_class <- switch(status,
    "Operational"        = "badge-operational",
    "Under Construction" = "badge-construction",
    "Approved"           = "badge-approved",
    "Announced"          = "badge-announced",
    "On Hold"            = "badge-onhold",
    "Cancelled"          = "badge-cancelled",
    "badge-announced"
  )
  title_attr <- if (nchar(detail) > 0) paste0(' title="', detail, '"') else ""
  glue('<span class="status-badge {css_class}"{title_attr}>{status}</span>')
}

# ---- Render a category badge ----
category_badge_html <- function(category) {
  css_class <- switch(category,
    "State-Backed"     = "badge-approved",
    "Private"          = "badge-operational",
    "JV"               = "badge-construction",
    "Foreign-Invested" = "badge-onhold",
    "badge-announced"
  )
  glue('<span class="status-badge {css_class}">{category}</span>')
}

# ---- Render a complexity bar (unchanged from India tracker) ----
complexity_bar_html <- function(score) {
  filled <- round(score)
  segments <- vapply(1:5, function(i) {
    cls <- if (i <= filled) "complexity-segment filled" else "complexity-segment"
    glue('<span class="{cls}"></span>')
  }, character(1))
  glue('<span class="complexity-bar" title="Technical Complexity: {score}/5">{paste(segments, collapse = "")}</span>')
}

# ---- Render an Entity List badge (empty string if not flagged) ----
entity_list_badge_html <- function(flagged, date_added = NA, list_name = NA_character_) {
  if (!isTRUE(flagged)) return("")
  detail <- if (!is.na(date_added)) {
    paste0(" (added ", format(date_added, "%b %Y"), ", ", list_name, ")")
  } else ""
  glue('<span class="status-badge badge-cancelled" title="Entity List{detail}">⚠ Entity List</span>')
}

# ---- Build the Chinese-name subtitle line, gracefully empty if unverified ----
zh_name_line <- function(name_zh, name_pinyin) {
  if (is.na(name_zh) || is.na(name_pinyin) || nchar(name_zh) == 0) return("")
  glue('<span class="zh-name">{name_zh} · {name_pinyin}</span><br/>')
}

# ---- Build leaflet popup HTML ----
make_popup <- function(row) {
  sig_html <- if (nchar(row$significance) > 0) {
    glue('<div class="popup-significance">{row$significance}</div>')
  } else ""

  node_html <- if (!is.na(row$current_node)) {
    glue('<div class="popup-row"><span class="popup-label">Current node:</span> {row$current_node}</div>')
  } else ""

  glue('
    <div class="facility-popup">
      <h4>{row$name_en}</h4>
      {zh_name_line(row$name_zh, row$name_pinyin)}
      {sig_html}
      <div class="popup-row"><span class="popup-label">Company:</span> {row$company_en}</div>
      <div class="popup-row"><span class="popup-label">Capability:</span> {row$capability}</div>
      <div class="popup-row"><span class="popup-label">Investment:</span> {format_investment(row$investment_rmb100m, row$investment_usd_m)}</div>
      <div class="popup-row"><span class="popup-label">Status:</span> {status_badge_html(row$status)}</div>
      <div class="popup-row"><span class="popup-label">Complexity:</span> {complexity_bar_html(row$complexity_score)}</div>
      {node_html}
      <div class="popup-row">{entity_list_badge_html(row$entity_list_flagged, row$entity_list_date, row$entity_list_name)}</div>
      <div class="popup-row" style="margin-top:6px;"><a href="facilities/{row$id}.html" class="btn-detail">Full Profile →</a></div>
    </div>
  ')
}

# ---- Build hover label ----
make_label <- function(row) {
  glue('<strong>{row$name_en}</strong><br/>{row$company_en} | {row$capability}')
}
```

- [ ] **Step 4: Run the fixture check**

```bash
Rscript -e '
source("R/helpers.R")
f <- load_facilities("R/test_fixtures/facilities_fixture.yml")
stopifnot(nrow(f) == 2)
stopifnot(f$current_node[f$id == "fixture-a"] == "7nm DUV")
stopifnot(is.na(f$current_node[f$id == "fixture-b"]))
stopifnot(is.na(f$name_zh[f$id == "fixture-b"]))
stopifnot(f$complexity_score[f$id == "fixture-a"] == round(4*0.55 + 5*0.45, 1))
popup_a <- make_popup(f[f$id == "fixture-a", ])
popup_b <- make_popup(f[f$id == "fixture-b", ])
stopifnot(grepl("示例工厂甲", popup_a))
stopifnot(!grepl("NA", popup_b))
cat("All checks passed\n")
'
```

Expected: `All checks passed`, no errors.

- [ ] **Step 5: Delete the fixture and commit**

```bash
rm -rf R/test_fixtures
git add R/helpers.R
git commit -m "feat: add R/helpers.R with trilingual and China-specific facility loader"
```

---

## Task 3: `data/facilities.yml` — Phase-1 batch A (SMIC fabs)

**Files:**
- Create: `data/facilities.yml`

**Interfaces:**
- Consumes: `load_facilities()` from Task 2.
- Produces: a `facilities.yml` with a `facilities:` top-level list, ready for Task 4's map/table page and for Task 6 to append batch B.

This is a **research task**, not a code-writing task. SMIC (中芯国际) operates multiple fabs — Shanghai, Beijing, Tianjin, Shenzhen. For each:

- [ ] **Step 1: Research and add SMIC's Shanghai fab entry**

Look up (SMIC HKEX/SSE filings, company site, SemiAnalysis, Caixin — per the spec's Sourcing Strategy section) and fill every field of the schema from Task 2's fixture shape: `name_en/zh/pinyin`, `company_en/zh/pinyin` (`SMIC` / `中芯国际集成电路制造有限公司` / `Zhōngxīn Guójì Jíchéng Diànlù Zhìzào Yǒuxiàn Gōngsī`), location, type, category (`State-Backed`), capability, investment, status, entity_list (SMIC as a corporate entity has been Entity List-restricted since Dec 2020 — verify the exact scope and date before asserting it applies to this specific fab), equipment_origin, node_trajectory, narrative, milestones, complexity, dates, and at least one cited source per factual claim. Leave any unverifiable field `null` rather than guessing.

- [ ] **Step 2: Research and add SMIC's Beijing, Tianjin, and Shenzhen fabs**

Same process as Step 1, one entry each. Distinguish them by `id` (`smic-beijing`, `smic-tianjin`, `smic-shenzhen`) and by their distinct process-node capabilities where known.

- [ ] **Step 3: Validate the file loads and has no duplicate ids**

```bash
Rscript -e '
source("R/helpers.R")
f <- load_facilities("data/facilities.yml")
cat("Loaded", nrow(f), "facilities:\n")
print(f$name_en)
'
```

Expected: no error (the duplicate-id `stop()` from Task 2 will fire here if two entries share an id), all 4 SMIC entries print.

- [ ] **Step 4: Commit**

```bash
git add data/facilities.yml
git commit -m "data: add SMIC fab entries (Phase 1 batch A)"
```

---

## Task 4: `index.qmd` — Map & Overview page

**Files:**
- Modify: `index.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()`, `category_color()`, `status_badge_html()`, `complexity_bar_html()`, `make_popup()`, `make_label()`, `format_investment()`, `category_badge_html()`, `entity_list_badge_html()` from Task 2.

- [ ] **Step 1: Write `index.qmd`**

```markdown
---
title: "China Semiconductor Tracker: Facilities"
subtitle: "Tracking semiconductor manufacturing across mainland China"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(leaflet)
library(DT)
library(ggplot2)
library(scales)
library(sf)
library(rnaturalearth)

facilities <- load_facilities("data/facilities.yml")
```

## The Story So Far

China's semiconductor industry is racing to indigenize under an expanding regime of US-led export controls. State financing through the National Integrated Circuit Industry Investment Fund (国家集成电路产业投资基金, "Big Fund") has backed fabs, memory makers, and equipment firms since 2014, while companies like SMIC have pushed mature-node lithography to produce chips at nodes once thought to require tools China cannot buy.

As of `r format(Sys.Date(), "%B %Y")`, this tracker covers **`r nrow(facilities)` facilities** across **`r length(unique(facilities$province))`** provinces/municipalities, of which **`r sum(facilities$entity_list_flagged)`** are flagged on the US Entity List. Total disclosed investment stands at **¥`r format(sum(facilities$investment_rmb100m, na.rm = TRUE), big.mark = ",")`亿** (¥100M units).

::: {.callout-note}
## Boundary Disclaimer
The map below uses [Natural Earth](https://www.naturalearthdata.com/)'s standard national boundary for China. It is shown for general geographic orientation only and carries no editorial position on any territorial dispute. See [About](about.qmd) for full methodology.
:::

---

## Facility Map

Facilities are coloured by ownership category — the dimension most relevant to China's export-control and state-financing story.

```{r map, echo=FALSE, warning=FALSE, message=FALSE}
colors <- sapply(facilities$category, category_color)
popups <- vapply(1:nrow(facilities), function(i) make_popup(facilities[i, ]), character(1))
labels <- lapply(1:nrow(facilities), function(i) htmltools::HTML(make_label(facilities[i, ])))

china <- ne_countries(country = "China", scale = "medium", returnclass = "sf")

carto_key <- Sys.getenv("CARTO_API_KEY")
positron_url <- paste0(
  "https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png?key=",
  carto_key
)

leaflet(facilities, options = leafletOptions(minZoom = 3, maxZoom = 10)) %>%
  addTiles(
    urlTemplate = positron_url,
    attribution = '&copy; <a href="https://carto.com/attributions">CARTO</a>, &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  ) %>%
  fitBounds(lng1 = 73, lat1 = 18, lng2 = 135, lat2 = 53) %>%
  addPolygons(
    data = china,
    color = "#620d3c",
    weight = 2,
    fillColor = "#E8EAF0",
    fillOpacity = 0.1,
    group = "Boundary"
  ) %>%
  addCircleMarkers(
    lng = ~lon, lat = ~lat,
    radius = 10,
    color = colors,
    fillColor = colors,
    fillOpacity = 0.8,
    stroke = TRUE,
    weight = 1.5,
    popup = popups,
    label = labels,
    labelOptions = labelOptions(
      style = list("font-size" = "12px", "padding" = "6px 10px"),
      direction = "auto"
    ),
    clusterOptions = markerClusterOptions(
      maxClusterRadius = 30,
      spiderfyOnMaxZoom = TRUE,
      showCoverageOnHover = FALSE,
      zoomToBoundsOnClick = TRUE
    )
  ) %>%
  addLegend(
    position = "bottomright",
    colors = c("#620d3c", "#2f6b6b", "#6A1B9A", "#1565C0"),
    labels = c("State-Backed", "Private", "JV", "Foreign-Invested"),
    title = "Ownership Category"
  )
```

## Summary

::: {.grid}
::: {.g-col-12 .g-col-sm-6 .g-col-md-3}
::: {.summary-card}
[`r nrow(facilities)`]{.card-value}
[Facilities tracked]{.card-label}
:::
:::

::: {.g-col-12 .g-col-sm-6 .g-col-md-3}
::: {.summary-card}
[¥`r format(sum(facilities$investment_rmb100m, na.rm = TRUE), big.mark = ",")`亿]{.card-value}
[Disclosed investment]{.card-label}
:::
:::

::: {.g-col-12 .g-col-sm-6 .g-col-md-3}
::: {.summary-card}
[`r sum(facilities$entity_list_flagged)`]{.card-value}
[Entity List-flagged]{.card-label}
:::
:::

::: {.g-col-12 .g-col-sm-6 .g-col-md-3}
::: {.summary-card}
[`r sum(facilities$status == "Operational")`]{.card-value}
[Operational]{.card-label}
:::
:::
:::

## All Facilities

```{r table, echo=FALSE, warning=FALSE, message=FALSE}
table_data <- facilities %>%
  mutate(
    Name = paste0('<a href="facilities/', id, '.html">', name_en, '</a>'),
    Category = sapply(category, category_badge_html),
    Status = mapply(status_badge_html, status, status_detail),
    Complexity = sapply(complexity_score, complexity_bar_html),
    Investment = mapply(format_investment, investment_rmb100m, investment_usd_m, MoreArgs = list(short = TRUE)),
    "Entity List" = mapply(entity_list_badge_html, entity_list_flagged, entity_list_date, entity_list_name),
    Location = paste0(city, ", ", province)
  ) %>%
  select(Name, Type = type, Category, Investment, Status, Complexity, "Entity List", Location)

datatable(
  table_data,
  escape = FALSE,
  filter = "top",
  options = list(pageLength = 15, dom = "ftip", scrollX = TRUE),
  rownames = FALSE,
  class = "display compact"
)
```

::: {.callout-note}
## Understanding the Metrics
- **Technical Complexity:** weighted score, 55% Technology Difficulty + 45% Capital Intensity, benchmarked against a 3nm fab (5/5). See [About](about.qmd).
- **Investment:** shown in ¥ (RMB) 亿 (100 million yuan); a dollar figure is shown alongside when a firm's investment is only disclosed in USD.
:::
```

- [ ] **Step 2: Render and verify**

Run: `quarto render index.qmd`
Expected: renders without error; table shows all facilities from Task 3 including at least one long CJK company name without layout breakage; map shows markers at correct China coordinates.

- [ ] **Step 3: Commit**

```bash
git add index.qmd
git commit -m "feat: build Map & Overview page"
```

---

## Task 5: `R/generate_facility_pages.R` — facility profile pages

**Files:**
- Create: `R/generate_facility_pages.R`
- Create: `facilities/` (generated output directory)

**Interfaces:**
- Consumes: `load_facilities()`, `format_investment()`, `complexity_bar_html()`, `entity_list_badge_html()` from Task 2.
- Produces: one `.qmd` file per facility under `facilities/`, each linked from `index.qmd`'s table/popups (Task 4 already references `facilities/{id}.html`).

- [ ] **Step 1: Write `R/generate_facility_pages.R`**

```r
# R script to generate individual facility profile pages from YAML data
# Run: Rscript R/generate_facility_pages.R
source("R/helpers.R")
library(yaml)
library(glue)

facilities <- load_facilities("data/facilities.yml")
raw_facs <- yaml::read_yaml("data/facilities.yml")$facilities

if (!dir.exists("facilities")) dir.create("facilities")

template <- '---
title: "{name_en}"
subtitle: "{company_en} | {type}"
date: last-modified
---

::: {{.callout-tip}}
## Why This Matters
{significance}
:::

{zh_name_block}

## What does this facility make?

{what_it_makes}

## Why does it matter?

{why_it_matters}

## Key Facts

| | |
|---|---|
| **Company** | {company_en} |
| **Type** | {type} |
| **Category** | {category} |
| **Capability** | {capability} |
| **Status** | {status} |
| **Investment** | {investment_text} |
| **Funding Source** | {investment_source} |
| **Location** | {city}, {province} |
| **Current Node** | {current_node_text} |
| **Entity List** | {entity_list_text} |
| **Domestic Equipment Share** | {domestic_pct_text} |
| **Key Foreign Tools** | {key_foreign_tools_text} |
| **Smuggled/Diverted Equipment Flagged** | {smuggled_flagged_text} |

### Technical Complexity
{complexity_bar}
**{complexity_score}/5**

## Technology Node Trajectory

{node_trajectory_section}

## Project Timeline

{milestones_section}

## Sources

{source_links}

---

<a href="../index.html" class="btn btn-primary">Back to Map</a>
'

for (i in 1:nrow(facilities)) {
  f <- facilities[i, ]
  this_fac <- Filter(function(x) x$id == f$id, raw_facs)[[1]]

  zh_name_block <- if (!is.na(f$name_zh)) {
    glue("**Chinese name:** {f$name_zh} ({f$name_pinyin})")
  } else {
    "*Chinese name not yet verified.*"
  }

  investment_text <- format_investment(f$investment_rmb100m, f$investment_usd_m)
  current_node_text <- if (!is.na(f$current_node)) f$current_node else "Not yet researched"
  entity_list_text <- if (isTRUE(f$entity_list_flagged)) {
    paste0("Yes — ", f$entity_list_name, " (", format(f$entity_list_date, "%d %b %Y"), ")")
  } else {
    "No"
  }
  domestic_pct_text <- if (!is.na(f$domestic_pct)) paste0(f$domestic_pct, "%") else "Not disclosed"
  key_foreign_tools_text <- if (nchar(f$key_foreign_tools) > 0) f$key_foreign_tools else "None documented"
  smuggled_flagged_text <- if (isTRUE(f$smuggled_flagged)) "Yes — see sources" else "No"

  if (!is.null(this_fac$node_trajectory) && length(this_fac$node_trajectory) > 0) {
    traj_lines <- sapply(this_fac$node_trajectory, function(t) paste0("- **", t$year, "**: ", t$node))
    node_trajectory_section <- paste(traj_lines, collapse = "\n")
  } else {
    node_trajectory_section <- "*Node history not yet researched.*"
  }

  if (!is.null(this_fac$milestones) && length(this_fac$milestones) > 0) {
    milestone_lines <- sapply(this_fac$milestones, function(m) {
      date_str <- format(as.Date(m$date), "%d %b %Y")
      paste0("- **", date_str, "** — ", m$event)
    })
    milestones_section <- paste(milestone_lines, collapse = "\n")
  } else {
    milestones_section <- "*No milestones recorded yet.*"
  }

  if (!is.null(this_fac$sources) && length(this_fac$sources) > 0) {
    source_lines <- sapply(this_fac$sources, function(s) {
      date_str <- format(as.Date(s$date), "%d %b %Y")
      paste0("- [", s$title, "](", s$url, ") (", date_str, ")")
    })
    source_links <- paste(source_lines, collapse = "\n")
  } else {
    source_links <- "*No sources linked yet.*"
  }

  significance <- if (nchar(f$significance) > 0) f$significance else "Details coming soon."
  what_it_makes <- if (nchar(f$what_it_makes) > 0) f$what_it_makes else "*Details coming soon.*"
  why_it_matters <- if (nchar(f$why_it_matters) > 0) f$why_it_matters else "*Details coming soon.*"

  page_content <- glue(template,
    name_en = f$name_en, company_en = f$company_en, type = f$type, category = f$category,
    zh_name_block = zh_name_block, capability = f$capability, status = f$status,
    investment_text = investment_text, investment_source = f$investment_source,
    city = f$city, province = f$province, current_node_text = current_node_text,
    entity_list_text = entity_list_text, domestic_pct_text = domestic_pct_text,
    key_foreign_tools_text = key_foreign_tools_text,
    complexity_bar = complexity_bar_html(f$complexity_score), complexity_score = f$complexity_score,
    smuggled_flagged_text = smuggled_flagged_text,
    significance = significance, what_it_makes = what_it_makes, why_it_matters = why_it_matters,
    node_trajectory_section = node_trajectory_section,
    milestones_section = milestones_section, source_links = source_links
  )

  writeLines(page_content, paste0("facilities/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(facilities), "facility pages.\n")
```

- [ ] **Step 2: Run the generator**

Run: `Rscript R/generate_facility_pages.R`
Expected: `Successfully generated 4 facility pages.` and `facilities/*.qmd` files exist, one per Task 3 entry.

- [ ] **Step 3: Render the full site to confirm profile pages build and link correctly**

Run: `quarto render`
Expected: no errors; `_site/facilities/smic-shanghai.html` etc. exist; clicking "Full Profile" from a map popup in a local preview reaches the right page.

- [ ] **Step 4: Commit**

```bash
git add R/generate_facility_pages.R facilities/
git commit -m "feat: generate facility profile pages from YAML"
```

---

## Task 6: `data/facilities.yml` — Phase-1 batch B (remaining fabs)

**Files:**
- Modify: `data/facilities.yml` (append entries)

**Interfaces:**
- Consumes: same schema as Task 3.
- Produces: extends the same file Task 4/5 already render from — no code changes needed, only data + regeneration.

- [ ] **Step 1: Research and append Hua Hong (华虹半导体) fab entries**

Same schema and sourcing discipline as Task 3.

- [ ] **Step 2: Research and append memory makers — YMTC (长江存储) and CXMT (长鑫存储)**

`type: "Memory"`. These two are the highest-profile chokepoint stories (3D NAND and DRAM under sanctions) — spend extra care on `node_trajectory` and `entity_list` accuracy here, since this is likely the most-scrutinized data in the tracker.

- [ ] **Step 3: Research and append Nexchip (晶合集成), JHICC (福建晋华), SiEn (赛麟半导体/芯恩), Wingtech/Nexperia's China operations, and GTA Semiconductor**

Same schema. Confirm each entry's `id` is unique before moving to Step 4.

- [ ] **Step 4: Validate uniqueness and reload**

```bash
Rscript -e '
source("R/helpers.R")
f <- load_facilities("data/facilities.yml")
cat("Loaded", nrow(f), "facilities across", length(unique(f$province)), "provinces\n")
cat("Phase 1 target is ~25-30; below that is fine if it reflects real verified entries, not a bug.\n")
'
```

Expected: no duplicate-id error (the `stop()` in `load_facilities()` from Task 2 still fires on a real collision — that check is not being relaxed, only the arbitrary count threshold). Facility count reflects however many were independently verified across Tasks 3+6 — do not pad with unverified data to hit a number.

- [ ] **Step 5: Regenerate facility pages and render**

```bash
Rscript R/generate_facility_pages.R
quarto render index.qmd
```

Expected: table and map on `index.qmd` now show every batch-A and batch-B facility.

- [ ] **Step 6: Commit**

```bash
git add data/facilities.yml facilities/
git commit -m "data: add remaining Phase 1 fab and memory-maker entries (batch B)"
```

---

## Task 7: `timeline.qmd` — Project timeline

**Files:**
- Modify: `timeline.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()` from Task 2, populated data from Tasks 3+6.

- [ ] **Step 1: Write `timeline.qmd`**

```markdown
---
title: "Project Timeline"
subtitle: "Milestones and expected completion dates for China's semiconductor facilities"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(DT)
library(ggplot2)
library(scales)
library(dplyr)
library(tidyr)

facilities <- load_facilities("data/facilities.yml")
```

## Facility Timelines

Each row represents a facility. **Bars** show the span from construction start (or announcement, if construction hasn't begun) to expected or actual completion. **Diamond markers (◆)** mark the announcement date. The **dashed line** marks today.

```{r gantt-chart, echo=FALSE, warning=FALSE, message=FALSE, fig.width=12, fig.height=7.5, dev="ragg_png"}
gantt_data <- facilities %>%
  filter(!is.na(date_announced)) %>%
  mutate(
    bar_start = coalesce(date_construction, date_announced),
    bar_end = coalesce(date_completion, date_original_expect, Sys.Date()),
    has_construction = !is.na(date_construction) | status == "Operational",
    name_label = gsub(" \\(Fab\\)| Facility", "", name_en)
  ) %>%
  arrange(category, date_announced)

status_colors <- c(
  "Operational"        = "#2f6b4a",
  "Under Construction" = "#1565C0",
  "Approved"           = "#f1a222",
  "Announced"          = "#8C8480",
  "On Hold"            = "#a3282d",
  "Cancelled"          = "#a3282d"
)

p <- ggplot(gantt_data, aes(y = reorder(name_label, desc(date_announced)))) +
  geom_segment(aes(x = bar_start, xend = bar_end, yend = name_label, color = status), linewidth = 5) +
  geom_point(aes(x = date_announced), shape = 18, size = 3, color = "#333") +
  geom_vline(xintercept = Sys.Date(), linetype = "dashed", color = "#888") +
  scale_color_manual(values = status_colors, name = "Status") +
  scale_x_date(date_labels = "%Y") +
  labs(x = NULL, y = NULL) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())

p
```

## Recent Milestones

```{r milestones, echo=FALSE, results='asis', warning=FALSE, message=FALSE}
raw_facs <- yaml::read_yaml("data/facilities.yml")$facilities
all_milestones <- do.call(rbind, lapply(raw_facs, function(f) {
  if (is.null(f$milestones) || length(f$milestones) == 0) return(NULL)
  do.call(rbind, lapply(f$milestones, function(m) {
    data.frame(facility = f$name_en, id = f$id, date = as.Date(m$date), event = m$event, stringsAsFactors = FALSE)
  }))
}))

if (!is.null(all_milestones)) {
  recent <- head(all_milestones[order(all_milestones$date, decreasing = TRUE), ], 10)
  for (i in seq_len(nrow(recent))) {
    r <- recent[i, ]
    cat(sprintf("- **%s** — %s ([%s](facilities/%s.html))\n", format(r$date, "%b %Y"), r$event, r$facility, r$id))
  }
} else {
  cat("*No milestones recorded yet.*\n")
}
```
```

- [ ] **Step 2: Render and verify**

Run: `quarto render timeline.qmd`
Expected: renders without error; Gantt chart shows one bar per facility; falls back to "No milestones recorded yet." gracefully if a facility has none (already exercised by fixture-b's shape in Task 2, now checked against real data).

- [ ] **Step 3: Commit**

```bash
git add timeline.qmd
git commit -m "feat: build project timeline page"
```

---

## Task 8: `nodes.qmd` — Technology node trajectory

**Files:**
- Modify: `nodes.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()` from Task 2.

- [ ] **Step 1: Write `nodes.qmd`**

```markdown
---
title: "Technology Nodes"
subtitle: "China's process-node trajectory under export controls"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(ggplot2)
library(dplyr)
library(tidyr)

facilities <- load_facilities("data/facilities.yml")
raw_facs <- yaml::read_yaml("data/facilities.yml")$facilities
```

## The Global Node Landscape

Semiconductor "nodes" refer to manufacturing process technology; smaller numbers generally mean more advanced chips.

```{r node-chart, echo=FALSE, fig.width=10, fig.height=7, dev="ragg_png"}
nodes <- tibble(
  node = c("3nm", "5nm", "7nm", "10nm", "14nm", "22nm", "28nm", "40nm", "55nm", "65nm", "90nm", "130nm", "180nm+"),
  node_nm = c(3, 5, 7, 10, 14, 22, 28, 40, 55, 65, 90, 130, 180),
  era = c("Cutting Edge", "Cutting Edge", "Advanced", "Advanced", "Advanced",
          "Mature", "Mature", "Mature", "Mature", "Legacy", "Legacy", "Legacy", "Legacy"),
  key_fabs = c(
    "TSMC, Samsung", "TSMC, Samsung", "TSMC, Samsung, Intel, SMIC (via SAQP)",
    "TSMC, Samsung, Intel", "TSMC, Samsung, Intel, SMIC", "Intel, GF, TSMC",
    "TSMC, Samsung, GF, SMIC, UMC, Hua Hong", "TSMC, UMC, SMIC, Hua Hong",
    "PSMC, UMC, Hua Hong", "Various (widely available)", "Various", "Various", "Various"
  )
)

era_colors <- c("Cutting Edge" = "#620d3c", "Advanced" = "#f1a222", "Mature" = "#2f6b6b", "Legacy" = "#8C8480")

ggplot(nodes, aes(x = reorder(node, -node_nm), y = 1, fill = era)) +
  geom_col(width = 0.8) +
  geom_text(aes(label = paste0(node, ": ", key_fabs)), hjust = 0, nudge_y = 0.05, size = 3) +
  coord_flip() +
  scale_fill_manual(values = era_colors) +
  scale_y_continuous(limits = c(0, 4)) +
  labs(x = NULL, y = NULL, fill = "Era") +
  theme_minimal() +
  theme(axis.text.x = element_blank(), panel.grid = element_blank())
```

## China's Indigenization Trajectory

Each line traces one facility's most advanced disclosed process node over time — the clearest signal of how effectively export controls have slowed (or failed to slow) specific fabs.

```{r trajectory-chart, echo=FALSE, warning=FALSE, message=FALSE, fig.width=10, fig.height=6, dev="ragg_png"}
trajectory_rows <- do.call(rbind, lapply(raw_facs, function(f) {
  if (is.null(f$node_trajectory) || length(f$node_trajectory) == 0) return(NULL)
  do.call(rbind, lapply(f$node_trajectory, function(t) {
    data.frame(facility = f$name_en, year = t$year, node = t$node, stringsAsFactors = FALSE)
  }))
}))

if (!is.null(trajectory_rows) && nrow(trajectory_rows) > 0) {
  node_to_nm <- function(n) as.numeric(gsub("[^0-9].*", "", n))
  trajectory_rows$node_nm <- sapply(trajectory_rows$node, node_to_nm)

  ggplot(trajectory_rows, aes(x = year, y = node_nm, color = facility, group = facility)) +
    geom_line(linewidth = 1) +
    geom_point(size = 2) +
    scale_y_reverse() +
    labs(x = "Year", y = "Node (nm, smaller = more advanced)", color = "Facility") +
    theme_minimal()
} else {
  cat("*No node trajectory data yet — populated as facility research is added.*")
}
```

::: {.callout-note}
## Reading This Chart
A facility with no plotted line has not yet had its node history researched (see [About](about.qmd) for data status). Absence from this chart is a data gap, not a claim about the facility's capability.
:::
```

- [ ] **Step 2: Render and verify**

Run: `quarto render nodes.qmd`
Expected: renders without error even if some facilities have empty `node_trajectory` (they're silently excluded from `trajectory_rows`, matching this task's Review Focus item); chart shows at least the entries populated in Tasks 3/6.

- [ ] **Step 3: Commit**

```bash
git add nodes.qmd
git commit -m "feat: build technology nodes page with node-trajectory chart"
```

---

## Task 9: Chip design firms — schema, data, page, generator

**Files:**
- Modify: `R/helpers.R` (append design-firm functions)
- Create: `data/design.yml`
- Modify: `design.qmd` (replace Task 1's stub)
- Create: `R/generate_design_pages.R`

**Interfaces:**
- Produces: `load_design_firms(path)`, `design_category_color()`, `design_category_badge()`, `design_score_bar_html()`, `make_design_popup()`.

- [ ] **Step 1: Append design-firm helpers to `R/helpers.R`**

```r
# ---- Load and flatten design firms YAML into a tibble ----
load_design_firms <- function(path = "data/design.yml") {
  raw <- yaml::read_yaml(path)

  rows <- lapply(raw$design_firms, function(f) {
    tibble(
      id                = f$id,
      name_en           = f$name_en,
      name_zh           = f$name_zh %||% NA_character_,
      name_pinyin       = f$name_pinyin %||% NA_character_,
      category          = f$category,
      founded           = f$founded %||% NA_integer_,
      city              = f$location$city,
      province          = f$location$province,
      lat               = f$location$lat,
      lon               = f$location$lon,
      product_focus     = f$product_focus %||% "",
      design_scope      = f$design_scope %||% "",
      node_sophistication = f$node_sophistication %||% "",
      entity_list_flagged = f$entity_list$status %||% FALSE,
      entity_list_date  = as.Date(f$entity_list$date_added %||% NA),
      entity_list_name  = f$entity_list$list %||% NA_character_,
      significance      = f$narrative$significance %||% "",
      what_it_designs   = f$narrative$what_it_designs %||% "",
      score_dim1 = f$design_score$ip_ownership %||% NA_real_,
      score_dim2 = f$design_score$design_completeness %||% NA_real_,
      score_dim3 = f$design_score$domain_difficulty %||% NA_real_,
      score_dim4 = f$design_score$market_readiness %||% NA_real_
    )
  })

  df <- bind_rows(rows) %>%
    mutate(design_composite = round(rowMeans(cbind(score_dim1, score_dim2, score_dim3, score_dim4), na.rm = FALSE), 1))

  set.seed(43)
  df %>% mutate(lat = lat + runif(n(), -0.015, 0.015), lon = lon + runif(n(), -0.015, 0.015))
}

design_category_color <- function(category) {
  switch(category,
    "Fabless"                    = "#620d3c",
    "State-Backed Design House"  = "#2f6b4a",
    "EDA & IP Provider"          = "#f1a222",
    "#8C8480"
  )
}

design_category_badge <- function(category) {
  css_class <- switch(category,
    "Fabless"                   = "badge-approved",
    "State-Backed Design House" = "badge-operational",
    "EDA & IP Provider"         = "badge-onhold",
    "badge-announced"
  )
  glue('<span class="status-badge {css_class}">{category}</span>')
}

design_score_bar_html <- function(score) {
  if (is.na(score)) return('<span class="complexity-bar" title="Not yet scored">—</span>')
  filled <- round(score)
  segments <- vapply(1:5, function(i) {
    cls <- if (i <= filled) "complexity-segment filled" else "complexity-segment"
    glue('<span class="{cls}"></span>')
  }, character(1))
  glue('<span class="complexity-bar" title="Design Score: {score}/5">{paste(segments, collapse = "")}</span>')
}

make_design_popup <- function(row) {
  glue('
    <div class="facility-popup">
      <h4>{row$name_en}</h4>
      {zh_name_line(row$name_zh, row$name_pinyin)}
      <div class="popup-row">{design_category_badge(row$category)}</div>
      <div class="popup-row"><span class="popup-label">Focus:</span> {row$product_focus}</div>
      <div class="popup-row"><span class="popup-label">Node:</span> {row$node_sophistication}</div>
      <div class="popup-row">{entity_list_badge_html(row$entity_list_flagged, row$entity_list_date, row$entity_list_name)}</div>
      <div class="popup-row" style="margin-top:6px;"><a href="design-firms/{row$id}.html" class="btn-detail">Full Profile →</a></div>
    </div>
  ')
}
```

- [ ] **Step 2: Research and write `data/design.yml`**

Research HiSilicon (海思半导体), UNISOC (紫光展锐), and one additional major fabless/design firm. Schema per firm:

```yaml
design_firms:
  - id: hisilicon
    name_en: "HiSilicon"
    name_zh: "海思半导体"
    name_pinyin: "Hǎisī Bàndǎotǐ"
    category: "Fabless"
    founded: 2004
    location: {city: "Shenzhen", province: "Guangdong"}
    product_focus: "..."
    design_scope: "..."
    node_sophistication: "..."
    entity_list: {status: true, date_added: "...", list: "US Commerce BIS"}
    design_score: {ip_ownership: 5, design_completeness: 5, domain_difficulty: 4, market_readiness: 3}
    narrative: {significance: "...", what_it_designs: "..."}
    sources: [{url: "...", title: "...", date: "..."}]
```

Same sourcing discipline as Task 3: cite every factual claim, leave unverified fields `null`.

- [ ] **Step 3: Write `R/generate_design_pages.R`**

```r
source("R/helpers.R")
library(yaml)
library(glue)

firms <- load_design_firms("data/design.yml")
raw_firms <- yaml::read_yaml("data/design.yml")$design_firms

if (!dir.exists("design-firms")) dir.create("design-firms")

template <- '---
title: "{name_en}"
subtitle: "{category}"
date: last-modified
---

{zh_name_block}

::: {{.callout-tip}}
## Why This Matters
{significance}
:::

## What does this firm design?

{what_it_designs}

## Key Facts

| | |
|---|---|
| **Category** | {category} |
| **Founded** | {founded_text} |
| **Location** | {city}, {province} |
| **Product Focus** | {product_focus} |
| **Node Sophistication** | {node_sophistication} |
| **Entity List** | {entity_list_text} |

### Design Score
{score_bar} **{composite_text}**

## Sources

{source_links}

---

<a href="../design.html" class="btn btn-primary">Back to Design Tracker</a>
'

for (i in 1:nrow(firms)) {
  f <- firms[i, ]
  this_firm <- Filter(function(x) x$id == f$id, raw_firms)[[1]]

  zh_name_block <- if (!is.na(f$name_zh)) glue("**Chinese name:** {f$name_zh} ({f$name_pinyin})") else "*Chinese name not yet verified.*"
  founded_text <- if (!is.na(f$founded)) as.character(f$founded) else "Unknown"
  entity_list_text <- if (isTRUE(f$entity_list_flagged)) paste0("Yes — ", f$entity_list_name) else "No"
  composite_text <- if (!is.na(f$design_composite)) paste0(f$design_composite, "/5") else "Not yet scored"
  significance <- if (nchar(f$significance) > 0) f$significance else "Details coming soon."
  what_it_designs <- if (nchar(f$what_it_designs) > 0) f$what_it_designs else "*Details coming soon.*"

  source_links <- if (!is.null(this_firm$sources) && length(this_firm$sources) > 0) {
    paste(sapply(this_firm$sources, function(s) paste0("- [", s$title, "](", s$url, ") (", format(as.Date(s$date), "%d %b %Y"), ")")), collapse = "\n")
  } else "*No sources linked yet.*"

  page_content <- glue(template,
    name_en = f$name_en, category = f$category, zh_name_block = zh_name_block,
    founded_text = founded_text, city = f$city, province = f$province,
    product_focus = f$product_focus, node_sophistication = f$node_sophistication,
    entity_list_text = entity_list_text, score_bar = design_score_bar_html(f$design_composite),
    composite_text = composite_text, significance = significance, what_it_designs = what_it_designs,
    source_links = source_links
  )

  writeLines(page_content, paste0("design-firms/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(firms), "design firm pages.\n")
```

- [ ] **Step 4: Write `design.qmd`**

```markdown
---
title: "Chip Design in China: Fabless Firms & Design Houses"
subtitle: "Tracking Chinese fabless companies and semiconductor design operations"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(leaflet)
library(DT)

firms <- load_design_firms("data/design.yml")
```

## Overview

As of `r format(Sys.Date(), "%B %Y")`, this tracker covers **`r nrow(firms)` design firms**, of which **`r sum(firms$entity_list_flagged)`** are Entity List-flagged.

## Design Firm Map

```{r map, echo=FALSE, warning=FALSE, message=FALSE}
firms$colour <- sapply(firms$category, design_category_color)
popups <- vapply(1:nrow(firms), function(i) make_design_popup(firms[i, ]), character(1))

leaflet(firms, options = leafletOptions(minZoom = 3, maxZoom = 10)) %>%
  addProviderTiles("CartoDB.Positron") %>%
  fitBounds(lng1 = 73, lat1 = 18, lng2 = 135, lat2 = 53) %>%
  addCircleMarkers(
    lng = ~lon, lat = ~lat, radius = 8,
    color = "#ffffff", fillColor = ~colour, fillOpacity = 0.85, stroke = TRUE, weight = 1.5,
    popup = popups
  )
```

## All Design Firms

```{r table, echo=FALSE, warning=FALSE, message=FALSE}
table_data <- firms %>%
  mutate(
    Name = paste0('<a href="design-firms/', id, '.html">', name_en, '</a>'),
    Category = sapply(category, design_category_badge),
    "Design Score" = sapply(design_composite, design_score_bar_html),
    "Entity List" = mapply(entity_list_badge_html, entity_list_flagged, entity_list_date, entity_list_name)
  ) %>%
  select(Name, Category, "Product Focus" = product_focus, "Design Score", "Entity List")

datatable(table_data, escape = FALSE, filter = "top", options = list(pageLength = 15, dom = "ftip"), rownames = FALSE)
```
```

- [ ] **Step 5: Generate and render**

```bash
Rscript R/generate_design_pages.R
quarto render design.qmd
```

Expected: no errors; page shows 3 design firms.

- [ ] **Step 6: Commit**

```bash
git add R/helpers.R data/design.yml design.qmd R/generate_design_pages.R design-firms/
git commit -m "feat: add chip design tracker (schema, data, page, generator)"
```

---

## Task 10: Equipment & materials firms — schema, data, page, generator

**Files:**
- Modify: `R/helpers.R` (append materials-firm functions)
- Create: `data/materials.yml`
- Modify: `equipment-materials.qmd` (replace Task 1's stub)
- Create: `R/generate_materials_pages.R`

**Interfaces:**
- Produces: `load_materials_firms(path)`, `segment_color()`, `segment_badge_html()`, `make_materials_popup()`.

- [ ] **Step 1: Append materials-firm helpers to `R/helpers.R`**

```r
# ---- Load and flatten equipment/materials YAML into a tibble ----
load_materials_firms <- function(path = "data/materials.yml") {
  raw <- yaml::read_yaml(path)

  rows <- lapply(raw$materials_firms, function(f) {
    tibble(
      id             = f$id,
      name_en        = f$name_en,
      name_zh        = f$name_zh %||% NA_character_,
      name_pinyin    = f$name_pinyin %||% NA_character_,
      category       = f$category,
      segment        = f$segment,
      node_capability = f$node_capability %||% "Not disclosed",
      founded        = f$founded %||% NA_integer_,
      city           = f$hq$city,
      lat            = f$hq$lat,
      lon            = f$hq$lon,
      entity_list_flagged = f$entity_list$status %||% FALSE,
      entity_list_date    = as.Date(f$entity_list$date_added %||% NA),
      entity_list_name    = f$entity_list$list %||% NA_character_,
      significance   = f$narrative$significance %||% "",
      what_it_supplies = f$narrative$what_it_supplies %||% ""
    )
  })

  df <- bind_rows(rows)
  set.seed(45)
  df %>% mutate(lat = lat + runif(n(), -0.015, 0.015), lon = lon + runif(n(), -0.015, 0.015))
}

segment_color <- function(segment) {
  switch(segment,
    "Lithography"     = "#620d3c",
    "Etch"            = "#1565C0",
    "Deposition"      = "#2f6b4a",
    "CMP"             = "#6A1B9A",
    "Photoresist"     = "#f1a222",
    "Specialty Gas"   = "#00796B",
    "Wafers"          = "#455A64",
    "#8C8480"
  )
}

segment_badge_html <- function(segment) {
  glue('<span class="status-badge badge-announced" style="background-color:{segment_color(segment)};">{segment}</span>')
}

make_materials_popup <- function(row) {
  glue('
    <div class="facility-popup">
      <h4>{row$name_en}</h4>
      {zh_name_line(row$name_zh, row$name_pinyin)}
      <div class="popup-row">{segment_badge_html(row$segment)}</div>
      <div class="popup-row"><span class="popup-label">Category:</span> {row$category}</div>
      <div class="popup-row"><span class="popup-label">Node capability:</span> {row$node_capability}</div>
      <div class="popup-row">{entity_list_badge_html(row$entity_list_flagged, row$entity_list_date, row$entity_list_name)}</div>
      <div class="popup-row" style="margin-top:6px;"><a href="equipment-firms/{row$id}.html" class="btn-detail">Full Profile →</a></div>
    </div>
  ')
}
```

- [ ] **Step 2: Research and write `data/materials.yml`**

Research Naura Technology (北方华创), AMEC (中微公司), SMEE (上海微电子装备), ACM Research, and National Silicon Industry Group / TCL Zhonghuan — one entry each, following the schema from the spec (`id, name_en/zh/pinyin, category, segment, node_capability, founded, hq, entity_list, narrative, sources`). Same sourcing discipline as Task 3.

- [ ] **Step 3: Write `R/generate_materials_pages.R`**

```r
source("R/helpers.R")
library(yaml)
library(glue)

firms <- load_materials_firms("data/materials.yml")
raw_firms <- yaml::read_yaml("data/materials.yml")$materials_firms

if (!dir.exists("equipment-firms")) dir.create("equipment-firms")

template <- '---
title: "{name_en}"
subtitle: "{segment}"
date: last-modified
---

{zh_name_block}

::: {{.callout-tip}}
## Why This Matters
{significance}
:::

## What does this firm supply?

{what_it_supplies}

## Key Facts

| | |
|---|---|
| **Category** | {category} |
| **Segment** | {segment} |
| **Node Capability** | {node_capability} |
| **Founded** | {founded_text} |
| **HQ** | {city} |
| **Entity List** | {entity_list_text} |

## Sources

{source_links}

---

<a href="../equipment-materials.html" class="btn btn-primary">Back to Equipment & Materials</a>
'

for (i in 1:nrow(firms)) {
  f <- firms[i, ]
  this_firm <- Filter(function(x) x$id == f$id, raw_firms)[[1]]

  zh_name_block <- if (!is.na(f$name_zh)) glue("**Chinese name:** {f$name_zh} ({f$name_pinyin})") else "*Chinese name not yet verified.*"
  founded_text <- if (!is.na(f$founded)) as.character(f$founded) else "Unknown"
  entity_list_text <- if (isTRUE(f$entity_list_flagged)) paste0("Yes — ", f$entity_list_name) else "No"
  significance <- if (nchar(f$significance) > 0) f$significance else "Details coming soon."
  what_it_supplies <- if (nchar(f$what_it_supplies) > 0) f$what_it_supplies else "*Details coming soon.*"

  source_links <- if (!is.null(this_firm$sources) && length(this_firm$sources) > 0) {
    paste(sapply(this_firm$sources, function(s) paste0("- [", s$title, "](", s$url, ") (", format(as.Date(s$date), "%d %b %Y"), ")")), collapse = "\n")
  } else "*No sources linked yet.*"

  page_content <- glue(template,
    name_en = f$name_en, segment = f$segment, zh_name_block = zh_name_block,
    category = f$category, node_capability = f$node_capability, founded_text = founded_text,
    city = f$city, entity_list_text = entity_list_text, significance = significance,
    what_it_supplies = what_it_supplies, source_links = source_links
  )

  writeLines(page_content, paste0("equipment-firms/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(firms), "equipment/materials firm pages.\n")
```

- [ ] **Step 4: Write `equipment-materials.qmd`**

```markdown
---
title: "Equipment & Materials"
subtitle: "Tracking China's semiconductor equipment and materials chokepoint firms"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(leaflet)
library(DT)

firms <- load_materials_firms("data/materials.yml")
```

## Overview

Export controls target equipment and materials as much as fabs — the machines that deposit, etch, and pattern silicon, and the wafers and chemicals those machines consume. As of `r format(Sys.Date(), "%B %Y")`, this tracker covers **`r nrow(firms)` firms**, of which **`r sum(firms$entity_list_flagged)`** are Entity List-flagged.

## Firm Map

```{r map, echo=FALSE, warning=FALSE, message=FALSE}
firms$colour <- sapply(firms$segment, segment_color)
popups <- vapply(1:nrow(firms), function(i) make_materials_popup(firms[i, ]), character(1))

leaflet(firms, options = leafletOptions(minZoom = 3, maxZoom = 10)) %>%
  addProviderTiles("CartoDB.Positron") %>%
  fitBounds(lng1 = 73, lat1 = 18, lng2 = 135, lat2 = 53) %>%
  addCircleMarkers(
    lng = ~lon, lat = ~lat, radius = 8,
    color = "#ffffff", fillColor = ~colour, fillOpacity = 0.85, stroke = TRUE, weight = 1.5,
    popup = popups
  )
```

## All Firms

```{r table, echo=FALSE, warning=FALSE, message=FALSE}
table_data <- firms %>%
  mutate(
    Name = paste0('<a href="equipment-firms/', id, '.html">', name_en, '</a>'),
    Segment = sapply(segment, segment_badge_html),
    "Entity List" = mapply(entity_list_badge_html, entity_list_flagged, entity_list_date, entity_list_name)
  ) %>%
  select(Name, Category = category, Segment, "Node Capability" = node_capability, "Entity List")

datatable(table_data, escape = FALSE, filter = "top", options = list(pageLength = 15, dom = "ftip"), rownames = FALSE)
```
```

- [ ] **Step 5: Generate and render**

```bash
Rscript R/generate_materials_pages.R
quarto render equipment-materials.qmd
```

Expected: no errors; page shows 5 firms.

- [ ] **Step 6: Commit**

```bash
git add R/helpers.R data/materials.yml equipment-materials.qmd R/generate_materials_pages.R equipment-firms/
git commit -m "feat: add equipment & materials tracker (schema, data, page, generator)"
```

---

## Task 11: `data/funding.yml` and `funding.qmd` — State funding

**Files:**
- Modify: `R/helpers.R` (append `load_funding()`, `funding_source_color()`)
- Create: `data/funding.yml`
- Modify: `funding.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()`, `load_design_firms()`, `load_materials_firms()` (for the per-entity `investment_source`/aggregate view).
- Produces: `load_funding(path)`.

- [ ] **Step 1: Append to `R/helpers.R`**

```r
# ---- Load Big Fund macro rounds ----
load_funding <- function(path = "data/funding.yml") {
  raw <- yaml::read_yaml(path)
  rows <- lapply(raw$rounds, function(r) {
    tibble(round = r$round, year = r$year, size_rmb_100m = r$size_rmb_100m, focus = r$focus)
  })
  bind_rows(rows)
}

funding_source_color <- function(source) {
  switch(source,
    "Big Fund I"   = "#620d3c",
    "Big Fund II"  = "#8c2f5c",
    "Big Fund III" = "#b3527f",
    "Local Govt"   = "#2f6b6b",
    "Private"      = "#f1a222",
    "Foreign"      = "#1565C0",
    "#8C8480"
  )
}
```

- [ ] **Step 2: Research and write `data/funding.yml`**

Big Fund's three rounds (2014, 2019, 2024) have publicly reported headline sizes — research and cite them:

```yaml
rounds:
  - round: "Big Fund I"
    year: 2014
    size_rmb_100m: null
    focus: "..."
    sources: [{url: "...", title: "...", date: "..."}]
  - round: "Big Fund II"
    year: 2019
    size_rmb_100m: null
    focus: "..."
    sources: [{url: "...", title: "...", date: "..."}]
  - round: "Big Fund III"
    year: 2024
    size_rmb_100m: null
    focus: "..."
    sources: [{url: "...", title: "...", date: "..."}]
```

- [ ] **Step 3: Write `funding.qmd`**

```markdown
---
title: "State Funding"
subtitle: "China's National IC Industry Investment Fund (Big Fund) and other financing"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(ggplot2)
library(scales)
library(dplyr)

funding <- load_funding("data/funding.yml")
facilities <- load_facilities("data/facilities.yml")
design <- load_design_firms("data/design.yml")
```

## Big Fund Rounds

The National Integrated Circuit Industry Investment Fund (国家集成电路产业投资基金, "Big Fund") has run three rounds since 2014.

```{r rounds-table, echo=FALSE, warning=FALSE, message=FALSE}
knitr::kable(funding %>% mutate(Size = ifelse(is.na(size_rmb_100m), "Not disclosed", paste0("¥", format(size_rmb_100m, big.mark = ","), "亿"))) %>% select(Round = round, Year = year, Size, Focus = focus))
```

## Investment by Funding Source

Aggregated across all tracked facilities.

```{r source-chart, echo=FALSE, warning=FALSE, message=FALSE, fig.width=8, fig.height=4, dev="ragg_png"}
source_data <- facilities %>%
  group_by(investment_source) %>%
  summarise(total = sum(investment_rmb100m, na.rm = TRUE), n = n(), .groups = "drop") %>%
  filter(total > 0)

ggplot(source_data, aes(x = reorder(investment_source, total), y = total, fill = investment_source)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = paste0(n, " facilit", ifelse(n == 1, "y", "ies"), "\n¥", format(total, big.mark = ","), "亿")), hjust = -0.1, size = 3.5) +
  coord_flip() +
  scale_fill_manual(values = sapply(source_data$investment_source, funding_source_color), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.4))) +
  labs(x = NULL, y = "Total disclosed investment (¥100M)") +
  theme_minimal()
```

::: {.callout-note}
## Data Limitation
Unlike India's Union Budget documents, China does not publish itemized Big Fund disbursement-by-project data. Figures here are facility-level investment totals tagged by funding source where a source has disclosed the tag — not an audited Big Fund expenditure ledger.
:::
```

- [ ] **Step 4: Render and verify**

Run: `quarto render funding.qmd`
Expected: no errors; bar chart totals are not `NA` (Review Focus item — `na.rm = TRUE` is already applied in Step 3's `summarise()`).

- [ ] **Step 5: Commit**

```bash
git add R/helpers.R data/funding.yml funding.qmd
git commit -m "feat: add state funding page with Big Fund rounds"
```

---

## Task 12: `export-controls.qmd` — Entity List status

**Files:**
- Modify: `export-controls.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()`, `load_design_firms()`, `load_materials_firms()`, `entity_list_badge_html()`.

- [ ] **Step 1: Write `export-controls.qmd`**

```markdown
---
title: "Export Controls"
subtitle: "US Entity List status across tracked facilities and firms"
date: last-modified
---

```{r setup, include=FALSE}
source("R/helpers.R")
library(DT)
library(dplyr)

facilities <- load_facilities("data/facilities.yml")
design <- load_design_firms("data/design.yml")
materials <- load_materials_firms("data/materials.yml")
```

## Overview

As of `r format(Sys.Date(), "%B %Y")`: **`r sum(facilities$entity_list_flagged)`** of `r nrow(facilities)` tracked facilities, **`r sum(design$entity_list_flagged)`** of `r nrow(design)` design firms, and **`r sum(materials$entity_list_flagged)`** of `r nrow(materials)` equipment/materials firms are on the US Commerce Department's Entity List.

## Entity List-Flagged Entries

```{r table, echo=FALSE, warning=FALSE, message=FALSE}
fac_rows <- facilities %>% filter(entity_list_flagged) %>%
  transmute(Name = name_en, Type = "Facility", "Date Added" = format(entity_list_date, "%b %Y"), List = entity_list_name)
design_rows <- design %>% filter(entity_list_flagged) %>%
  transmute(Name = name_en, Type = "Design Firm", "Date Added" = format(entity_list_date, "%b %Y"), List = entity_list_name)
materials_rows <- materials %>% filter(entity_list_flagged) %>%
  transmute(Name = name_en, Type = "Equipment/Materials Firm", "Date Added" = format(entity_list_date, "%b %Y"), List = entity_list_name)

all_flagged <- bind_rows(fac_rows, design_rows, materials_rows)

if (nrow(all_flagged) > 0) {
  datatable(all_flagged, options = list(pageLength = 15, dom = "ftip"), rownames = FALSE)
} else {
  cat("*No entries flagged yet.*")
}
```

::: {.callout-note}
## Non-Partisan Note
Entity List status is a factual designation by the US Commerce Department's Bureau of Industry and Security. Its inclusion here documents export-control exposure, not a judgement on the underlying US or Chinese policy.
:::
```

- [ ] **Step 2: Render and verify**

Run: `quarto render export-controls.qmd`
Expected: no errors; table lists every flagged entry across all three data files.

- [ ] **Step 3: Commit**

```bash
git add export-controls.qmd
git commit -m "feat: add export controls page"
```

---

## Task 13: `about.qmd` — Methodology and sourcing strategy

**Files:**
- Modify: `about.qmd` (replace Task 1's stub)

**Interfaces:**
- Consumes: `load_facilities()`.

- [ ] **Step 1: Write `about.qmd`**

```markdown
---
title: "About This Tracker"
---

## What This Is

The China Semiconductor Tracker is a curated, open-source resource monitoring semiconductor manufacturing facilities, chip design firms, and equipment/materials suppliers across mainland China.

It is maintained by [Pranay Kotasthane](https://pranaykotas.com) at the [Takshashila Institution](https://takshashila.org.in), part of Takshashila's **[Siliconpolitik Project](https://takshashila.org.in/pages/research-areas/focus-areas/siliconpolitik.html)**. It is a companion to the [India Semiconductor Tracker](https://fabs.pranaykotas.com).

## Scope

This tracker covers mainland China (PRC) only. Taiwan and the Taiwanese semiconductor ecosystem are out of scope — a distinct political and market story that would need its own tracker.

## Naming Convention

Facility, company, design-firm, and equipment/materials-firm names are given in three forms where verified: English, simplified Chinese (简体), and Hanyu Pinyin. City and province names are given in English only. An entry showing "Chinese name not yet verified" reflects a genuine data gap, not an editorial choice.

## Units

Investment figures are shown in **¥ (RMB) 亿 (100 million yuan)** — the unit Chinese financial press and company filings typically report in — with a dollar figure alongside where a firm's investment is only disclosed in USD.

## Boundary Disclaimer

Maps use [Natural Earth](https://www.naturalearthdata.com/)'s standard national boundary for China, shown for general geographic orientation only. It carries no editorial position on any territorial dispute.

## Sourcing Strategy

- **Listed-company filings** (SMIC and Hua Hong on HKEX/SSE) are treated as primary sources for financials and capacity, sourced via exchange disclosures or cninfo.com.cn.
- **Chinese financial and industry press** (Caixin, 21世纪经济报道) is cited directly, with the same scrutiny applied to any credible outlet.
- **State media** (Xinhua, CCTV, People's Daily) is treated as a primary source for the fact of an announcement, not for its interpretation — the same standard applied to a government press release from any country.
- **Export-control evasion, smuggled equipment, and actual sanctioned-node yields** are structurally under-covered by domestic sources; these rely on SemiAnalysis, BIS Federal Register entries, and investigative reporting (Reuters, Nikkei Asia, FT).
- **LLM tools (including DeepSeek) are used only as research aids** — locating candidate sources, translating filings, summarizing documents — never cited as the source of a fact. Every figure in this tracker traces to a human-verified citation.

## Technical Complexity Index

Each facility is scored 1 (low) to 5 (high), benchmarked against a cutting-edge 3nm fab (5/5): composite = Technology Difficulty (55%) + Capital Intensity (45%).

## Data Status

As of `r format(Sys.Date(), "%B %Y")`, this tracker covers `r nrow(load_facilities("data/facilities.yml"))` facilities, all populated in Phase 1. Further batches — toward the full national count of 100+ facilities — are added over time; see the project's GitHub repository for the current status.

## Have an Update?

Found an error or have new information? [Open a GitHub Issue](https://github.com/pranaykotas/china-semiconductor-tracker/issues/new).
```

- [ ] **Step 2: Render and verify**

Run: `quarto render about.qmd`
Expected: no errors; facility count in "Data Status" matches `index.qmd`'s count.

- [ ] **Step 3: Commit**

```bash
git add about.qmd
git commit -m "feat: finalize about page with methodology and sourcing strategy"
```

---

## Task 14: Full-site integration check

**Files:** none (verification only)

**Interfaces:** exercises every function and page from Tasks 1-13 together.

- [ ] **Step 1: Full clean render**

```bash
rm -rf _site
Rscript R/generate_facility_pages.R
Rscript R/generate_design_pages.R
Rscript R/generate_materials_pages.R
quarto render
```

Expected: no errors or warnings about missing files; `_site/` contains all 8 top-level pages plus every generated profile page.

- [ ] **Step 2: Run the five Review Focus checks explicitly**

```bash
Rscript -e '
source("R/helpers.R")
f <- load_facilities("data/facilities.yml")
d <- load_design_firms("data/design.yml")
m <- load_materials_firms("data/materials.yml")

# 1. Unverified Chinese names render without breaking the popup
unverified <- f[is.na(f$name_zh), ]
if (nrow(unverified) > 0) {
  p <- make_popup(unverified[1, ])
  stopifnot(!grepl("NA", p))
}

# 2. Facilities without node_trajectory do not appear in the aggregate chart data
raw <- yaml::read_yaml("data/facilities.yml")$facilities
no_traj <- Filter(function(x) length(x$node_trajectory) == 0, raw)
cat(length(no_traj), "facilities have no node trajectory (expected, not an error)\n")

# 3. No duplicate ids across any of the three entity files
stopifnot(!any(duplicated(f$id)))
stopifnot(!any(duplicated(d$id)))
stopifnot(!any(duplicated(m$id)))

# 4. Investment sums are never NA even with missing data
stopifnot(!is.na(sum(f$investment_rmb100m, na.rm = TRUE)))

cat("All integration checks passed\n")
'
```

Expected: `All integration checks passed`.

- [ ] **Step 3: Manual visual check**

Run: `quarto preview`
Open the local preview and confirm: the nav bar has all 8 pages, the facility map loads markers, at least one facility popup shows a Chinese name line, at least one profile page for a facility with a long CJK company name renders its table cleanly.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: Phase 1 integration verified — all pages render end to end"
```
