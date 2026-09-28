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
      # Month-precision only: several source milestone dates are only known
      # to the month (or year), not the day — a stored day-of-month is a
      # storage convenience for sorting, not a verified fact, so it is never
      # displayed at day precision.
      date_str <- format(as.Date(m$date), "%b %Y")
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
