# R script to generate individual facility profile pages from YAML data
# Run: Rscript R/generate_facility_pages.R
source("R/helpers.R")
library(yaml)
library(glue)

facilities <- load_facilities("data/facilities.yml")
raw_facs <- yaml::read_yaml("data/facilities.yml")$facilities

if (!dir.exists("facilities")) dir.create("facilities")
remove_orphan_pages("facilities", facilities$id)

SITE_URL <- "https://fabs-china.pranaykotas.com"
yaml_safe <- function(s) gsub('"', "", s)

template <- '---
title: "{title}"
subtitle: "{company_en} | {type}"
description: "{description}"
date: last-modified
format:
  html:
    open-graph:
      image: "{image}"
    twitter-card:
      card: summary_large_image
      image: "{image}"
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
| **Capacity** | {capacity_text} |
| **Investment** | {investment_text} |
| **Funding Source** | {investment_source} |
| **Location** | {city}, {province} |
| **Current Node** | {current_node_text} |
| **Entity List** | {entity_list_text} |
{equipment_rows}| **Last Verified** | {last_verified_text} |

### Technical Complexity
{complexity_bar}
**{complexity_score}/5**

## {trajectory_heading}

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
  current_node_text <- if (f$type == "Assembly & Packaging") {
    "Not applicable (assembly & test)"
  } else if (!is.na(f$current_node)) f$current_node else "Not yet researched"
  entity_list_text <- if (isTRUE(f$entity_list_flagged)) {
    paste0("Yes — ", f$entity_list_name, " (", format(f$entity_list_date, "%d %b %Y"), ")")
  } else {
    "No"
  }
  # Equipment-origin rows are shown only once a facility's equipment base has
  # actually been researched. Showing "No" for smuggled equipment on an
  # unassessed facility would read as a verified negative finding.
  equipment_rows <- if (isTRUE(f$equipment_assessed)) {
    domestic_pct_text <- if (!is.na(f$domestic_pct)) paste0(f$domestic_pct, "%") else "Not disclosed"
    key_foreign_tools_text <- if (nchar(f$key_foreign_tools) > 0) f$key_foreign_tools else "None documented"
    smuggled_flagged_text <- if (isTRUE(f$smuggled_flagged)) "Yes — see sources" else "None reported"
    paste0(
      "| **Domestic Equipment Share** | ", domestic_pct_text, " |\n",
      "| **Key Foreign Tools** | ", key_foreign_tools_text, " |\n",
      "| **Smuggled/Diverted Equipment** | ", smuggled_flagged_text, " |\n"
    )
  } else {
    "| **Equipment Origin** | Not yet assessed |\n"
  }

  capacity_text <- format_capacity(this_fac$capacity)

  # Freshness: an explicit last_verified date wins; otherwise show the date
  # of the newest cited source, labelled as such so it is not mistaken for a
  # verification date.
  last_verified_text <- if (!is.na(f$last_verified)) {
    format(f$last_verified, "%d %b %Y")
  } else if (!is.na(f$latest_source_date)) {
    paste0("Not recorded (newest source dated ", format(f$latest_source_date, "%b %Y"), ")")
  } else {
    "Not recorded"
  }

  # OSAT sites have no process node; their equivalent is the sequence of
  # packaging technologies brought into production.
  if (f$type == "Assembly & Packaging") {
    trajectory_heading <- "Packaging Technology Trajectory"
    node_trajectory_section <- trajectory_md(this_fac$packaging_trajectory, "technology", "*Packaging technology history not yet researched.*")
  } else {
    trajectory_heading <- "Technology Node Trajectory"
    node_trajectory_section <- trajectory_md(this_fac$node_trajectory, "node", "*Node history not yet researched.*")
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

  title <- if (!is.na(f$name_zh) && nchar(f$name_zh) > 0) paste0(f$name_en, " · ", f$name_zh) else f$name_en

  page_content <- glue(template,
    title = yaml_safe(title),
    description = yaml_safe(social_description(f$significance)),
    image = paste0(SITE_URL, "/images/cards/facility-", f$id, ".png"),
    name_en = f$name_en, company_en = f$company_en, type = f$type, category = f$category,
    zh_name_block = zh_name_block, capability = f$capability, status = f$status,
    investment_text = investment_text, investment_source = f$investment_source,
    city = f$city, province = f$province, current_node_text = current_node_text,
    entity_list_text = entity_list_text, equipment_rows = equipment_rows,
    capacity_text = capacity_text, last_verified_text = last_verified_text,
    complexity_bar = complexity_bar_html(f$complexity_score), complexity_score = f$complexity_score,
    significance = significance, what_it_makes = what_it_makes, why_it_matters = why_it_matters,
    node_trajectory_section = node_trajectory_section, trajectory_heading = trajectory_heading,
    milestones_section = milestones_section, source_links = source_links
  )

  writeLines(page_content, paste0("facilities/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(facilities), "facility pages.\n")
