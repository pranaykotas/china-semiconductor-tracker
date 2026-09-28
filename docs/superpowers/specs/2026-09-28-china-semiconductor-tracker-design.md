# China Semiconductor Tracker — Design Spec

Date: 2026-09-28
Author: Pranay Kotasthane (with Claude Code)
Status: Approved for Phase 1 planning

## Purpose

An interactive, open-source tracker for China's semiconductor manufacturing sector, modeled on the existing [India Semiconductor Tracker](https://fabs.pranaykotas.com) (`../techgeopolitics`). Tracks fabs, ATMP/OSAT facilities, and chip design firms across mainland China (PRC), with facility and company names given in Chinese, pinyin, and English — and China-specific fields (US Entity List status, Big Fund financing, equipment origin, technology-node trajectory under export controls) that the India tracker does not need.

Intended as a companion site to the India tracker under Pranay's semiconductor-geopolitics work at the Takshashila Institution, feeding the same audience: policy researchers, journalists, and the informed public tracking global chip supply-chain shifts.

## Why This Differs From the India Tracker

| Dimension | India Tracker | China Tracker |
|---|---|---|
| Facility count | 16 | 100+ nationally; ~25-30 in Phase 1 |
| Names | English only | English + Chinese (简体) + Hanyu Pinyin |
| Core narrative | Industrial policy execution, slippage | Export-control resilience, state financing, indigenization pace |
| Sensitive framing | Low | Higher — sanctions, entity-list status, state subsidy require careful non-partisan framing per Takshashila house style |
| Data availability | Government press releases (PIB), company filings | Mix of company disclosures, SemiAnalysis/TrendForce analysis, SCMP/Nikkei reporting, BIS Entity List — more synthesis required, less official-source density |

## Scope

**In scope (Phase 1):**
- Mainland China (PRC) semiconductor manufacturing facilities: fabs, ATMP/OSAT, compound semiconductor, memory
- ~25-30 top-tier facilities covering all major players: SMIC (multiple fabs), Hua Hong, YMTC, CXMT, Nexchip, JHICC, SiEn, Wingtech/Nexperia, GTA Semiconductor, and others as researched
- 2-3 major fabless/IDM design firms for a design page (HiSilicon, UNISOC, others as researched)
- Trilingual facility and company names (English / Chinese / Pinyin)
- China-specific fields: Entity List status, Big Fund (国家集成电路产业投资基金) financing rounds, equipment origin (domestic vs. foreign vs. flagged-as-smuggled), year-by-year technology-node trajectory

**Explicitly out of scope (for now, revisit later):**
- Taiwan / TSMC and the broader Taiwanese semiconductor ecosystem — a distinct political and market story; deserves its own tracker, not a bolt-on comparison layer
- Real-time news/commentary scraping (contrast with the separate `TrackingPeoplesDaily` project)
- Full upstream equipment-maker or materials-supplier tracking beyond the per-facility `equipment_origin` field
- The remaining ~70+ facilities beyond Phase 1's ~25-30 — added in later batches, each its own research-then-populate cycle

## Architecture

Fork the `techgeopolitics` repository structure rather than building a new stack. Same tools, same author, same skill set (Quarto: advanced; R: beginner-comfortable) — the biggest lift here is data research and schema extension, not tooling.

- **Quarto website**, configured in `_quarto.yml`, output to `_site/`
- **Theme:** same Takshashila brand tokens as the India tracker (Cosmo + `styles.scss`, Llama maroon `#620d3c`, Marigold gold `#f1a222`, Inter body text, Roboto Mono for meta/eyebrow) for visual consistency across the two sites
- **Pages:**
  - `index.qmd` — Map & Overview (leaflet map of China, facility table)
  - `timeline.qmd` — Timeline of announcements/construction/operational milestones
  - `nodes.qmd` — Technology Nodes trajectory (node-shrink-over-time visualization)
  - `design.qmd` — Chip Design firms (fabless/IDM)
  - `funding.qmd` — State Funding (Big Fund rounds, local government investment) — replaces India tracker's `budget.qmd`
  - `export-controls.qmd` — Entity List status across facilities (new page, no India equivalent)
  - `about.qmd` — About / methodology / sourcing notes
- **All facility data** lives in `data/facilities.yml` (single source of truth, same pattern as India tracker)
- **Design firm data** in `data/design.yml` (separate schema, same pattern)
- **R helper functions** in `R/helpers.R` — extended from the India tracker's version

### Data Flow

```
data/facilities.yml  →  R/helpers.R (load_facilities())       →  .qmd pages (map, table, charts, node trajectory)
data/design.yml      →  R/helpers.R (load_design_firms())     →  design.qmd
```

Routine updates only require editing YAML files. No R code changes needed for adding facilities within the existing schema.

## Facility Data Schema (`data/facilities.yml`)

```yaml
- id: smic-shanghai
  name_en: "SMIC Shanghai (Fab)"
  name_zh: "中芯国际上海"
  name_pinyin: "Zhōngxīn Guójì Shànghǎi"
  company_en: "SMIC"
  company_zh: "中芯国际集成电路制造有限公司"
  company_pinyin: "Zhōngxīn Guójì Jíchéng Diànlù Zhìzào Yǒuxiàn Gōngsī"
  partners: []
  location:
    city: "Shanghai"
    province: "Shanghai Municipality"
    lat: 31.230
    lon: 121.474
  type: "Fab"                      # Fab | Assembly & Packaging | Compound Semiconductor | Memory | Research Fab
  category: "State-Backed"         # State-Backed | Private | JV | Foreign-Invested
  investment:
    total_rmb: 0                   # in RMB, units documented in about.qmd
    source: "Big Fund II"          # Big Fund I/II/III | Local Govt | Private | Foreign
  status: "Operational"            # Announced | Approved | Under Construction | Operational | On Hold | Cancelled
  entity_list:
    status: true
    date_added: "2020-12-18"
    list: "US Commerce BIS"
  equipment_origin:
    domestic_pct: 30
    key_foreign_tools: ["ASML DUV", "Applied Materials deposition"]
    smuggled_flagged: false
  node_trajectory:
    - {year: 2019, node: "14nm"}
    - {year: 2024, node: "7nm DUV (SAQP)"}
  narrative:
    significance: "One sentence — why should a non-expert care?"
    what_it_makes: "What does this facility produce?"
    why_it_matters: "Broader strategic significance"
  milestones:
    - {date: "2020-12-18", event: "Added to US Entity List"}
  complexity:
    technology_difficulty: 4       # 1-5, benchmarked against 3nm fab = 5
    foreign_dependence: 4
    capital_intensity: 5
  dates:
    announced: "..."
    approved: "..."
    construction_start: "..."
    original_expected_completion: "..."
    date_completion: "..."
  sources:
    - {url: "...", title: "...", date: "..."}
```

Trilingual treatment applies only to `name_*` and `company_*` fields, per decision — city/province names stay English-only (standard romanization is already the legible default; tripling every location field would add maintenance cost without much reader value).

## R Layer Changes (`R/helpers.R`)

- `load_facilities()` extended to surface `_zh` / `_pinyin` fields and the new China-specific fields (`entity_list`, `equipment_origin`, `node_trajectory`, `investment$source`)
- New helper functions:
  - `entity_list_badge_html()` — renders a badge if a facility is Entity List-flagged
  - `node_trajectory_chart()` — small sparkline-style chart showing node shrink over time, for use on `nodes.qmd` and facility profile pages
  - `funding_source_color()` — color mapping for Big Fund I/II/III vs. local government vs. private vs. foreign
- Popup/table HTML (`make_popup()`) shows the English name as primary, with Chinese + pinyin as a subtitle line, e.g.:
  ```html
  <strong>SMIC Shanghai</strong><br>
  <span class="zh-name">中芯国际上海 · Zhōngxīn Guójì Shànghǎi</span>
  ```

## Deployment

Same pattern as the India tracker:
- GitHub Pages, weekly automated rebuild via GitHub Actions
- Own subdomain (naming TBD by Pranay — e.g. `fabs-china.pranaykotas.com`)
- CC BY 4.0 license
- Community-update path via GitHub Issue template, introduced once Phase 1 data is stable (not needed for the first commit)

## Phasing

**Phase 1** (this spec's implementation plan): schema, R helpers, all Quarto pages built and rendering correctly, populated with ~25-30 top-tier facilities and 2-3 design firms — enough to make every page (map, timeline, nodes, funding, export-controls) non-empty and demonstrate the full schema end to end.

**Later phases** (not covered by this spec, each its own research-then-populate cycle): additional batches of facilities toward the full 100+ national count; community contribution workflow; possible Taiwan/TSMC comparison tracker as a separate project.

## Open Items for Implementation Planning

- Exact list of ~25-30 Phase 1 facilities and their data (research task, not a design decision — to be compiled during implementation)
- Subdomain name
- RMB units convention (crore-equivalent, or plain yuan/billion yuan) — needs a documented convention in `about.qmd`, mirroring how the India tracker documents crore
