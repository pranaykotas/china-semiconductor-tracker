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
