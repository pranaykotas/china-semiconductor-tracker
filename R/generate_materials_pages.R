source("R/helpers.R")
library(yaml)
library(glue)

firms <- load_materials_firms("data/materials.yml")
raw_firms <- yaml::read_yaml("data/materials.yml")$materials_firms

if (!dir.exists("equipment-firms")) dir.create("equipment-firms")
remove_orphan_pages("equipment-firms", firms$id)

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
| **Capacity** | {capacity_text} |
| **Entity List** | {entity_list_text} |
| **Last Verified** | {last_verified_text} |

## Capability Trajectory

{capability_section}

## Manufacturing Sites in China

{sites_section}

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

  capacity_text <- format_capacity(this_firm$capacity)
  capability_section <- trajectory_md(this_firm$capability_trajectory, "capability", "*Capability history not yet researched.*")

  # Actual production sites only — sales, service, and training offices are
  # deliberately excluded (see About page).
  sites_section <- if (!is.null(this_firm$manufacturing_sites) && length(this_firm$manufacturing_sites) > 0) {
    paste(vapply(this_firm$manufacturing_sites, function(m) {
      paste0("- **", m$name, "** (", m$city, ") — ", m$what)
    }, character(1)), collapse = "\n")
  } else "*Production sites not yet researched.*"

  # Same freshness rule as facility pages: explicit date, else newest source
  source_dates <- as.Date(vapply(this_firm$sources %||% list(), function(s) as.character(s$date), character(1)))
  last_verified_text <- if (!is.na(f$last_verified)) {
    format(f$last_verified, "%d %b %Y")
  } else if (length(source_dates) > 0) {
    paste0("Not recorded (newest source dated ", format(max(source_dates), "%b %Y"), ")")
  } else "Not recorded"

  source_links <- if (!is.null(this_firm$sources) && length(this_firm$sources) > 0) {
    paste(sapply(this_firm$sources, function(s) paste0("- [", s$title, "](", s$url, ") (", format(as.Date(s$date), "%d %b %Y"), ")")), collapse = "\n")
  } else "*No sources linked yet.*"

  page_content <- glue(template,
    name_en = f$name_en, segment = f$segment, zh_name_block = zh_name_block,
    category = f$category, node_capability = f$node_capability, founded_text = founded_text,
    city = f$city, entity_list_text = entity_list_text, significance = significance,
    what_it_supplies = what_it_supplies, source_links = source_links,
    capacity_text = capacity_text, last_verified_text = last_verified_text,
    capability_section = capability_section, sites_section = sites_section
  )

  writeLines(page_content, paste0("equipment-firms/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(firms), "equipment/materials firm pages.\n")
