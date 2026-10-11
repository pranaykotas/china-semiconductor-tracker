source("R/helpers.R")
library(yaml)
library(glue)

firms <- load_design_firms("data/design.yml")
raw_firms <- yaml::read_yaml("data/design.yml")$design_firms

if (!dir.exists("design-firms")) dir.create("design-firms")
remove_orphan_pages("design-firms", firms$id)

SITE_URL <- "https://fabs-china.pranaykotas.com"
yaml_safe <- function(s) gsub('"', "", s)

template <- '---
title: "{title}"
subtitle: "{category}"
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
| **Last Verified** | {last_verified_text} |

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

  # Freshness: design entries have no explicit last_verified field, so show
  # the newest cited source — labelled as such, never as a verification date.
  last_verified_text <- if (!is.na(f$latest_source_date)) {
    paste0("Newest source dated ", format(f$latest_source_date, "%d %b %Y"), " (", f$n_sources, " sources)")
  } else "Not recorded — no dated sources yet"
  title <- if (!is.na(f$name_zh) && nchar(f$name_zh) > 0) paste0(f$name_en, " · ", f$name_zh) else f$name_en

  source_links <- if (!is.null(this_firm$sources) && length(this_firm$sources) > 0) {
    paste(sapply(this_firm$sources, function(s) paste0("- [", s$title, "](", s$url, ") (", format(as.Date(s$date), "%d %b %Y"), ")")), collapse = "\n")
  } else "*No sources linked yet.*"

  page_content <- glue(template,
    title = yaml_safe(title),
    description = yaml_safe(social_description(f$significance)),
    image = paste0(SITE_URL, "/images/cards/design-", f$id, ".png"),
    name_en = f$name_en, category = f$category, zh_name_block = zh_name_block,
    founded_text = founded_text, city = f$city, province = f$province,
    product_focus = f$product_focus, node_sophistication = f$node_sophistication,
    last_verified_text = last_verified_text,
    entity_list_text = entity_list_text, score_bar = design_score_bar_html(f$design_composite),
    composite_text = composite_text, significance = significance, what_it_designs = what_it_designs,
    source_links = source_links
  )

  writeLines(page_content, paste0("design-firms/", f$id, ".qmd"))
}

cat("Successfully generated", nrow(firms), "design firm pages.\n")
