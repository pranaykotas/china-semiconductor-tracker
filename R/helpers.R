# helpers.R — Shared functions for the China Semiconductor Tracker
library(yaml)
library(dplyr)
library(tidyr)
library(glue)
library(htmltools)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---- Newest source date in an entry's sources[] list (NA when unlisted) ----
max_source_date <- function(sources) {
  if (is.null(sources) || length(sources) == 0) return(as.Date(NA))
  ds <- suppressWarnings(as.Date(vapply(sources, function(s) as.character(s$date %||% ""), character(1))))
  suppressWarnings(max(ds, na.rm = TRUE))
}

# ---- First sentence of the narrative, safe as an og:description meta tag ----
social_description <- function(text, max_chars = 155) {
  if (is.na(text) || nchar(text) == 0) return("Part of the China Semiconductor Tracker.")
  sentences <- strsplit(text, "(?<=[.!?])\\s", perl = TRUE)[[1]]
  sentence <- trimws(sentences[1])
  if (nchar(sentence) > max_chars) sentence <- paste0(substr(sentence, 1, max_chars), "…")
  gsub('["\u201c\u201d]', "", sentence)  # quotes would break the YAML meta string
}

# ---- Normalise a raw entity_list$list string to a short dashboard label ----
designation_label <- function(list_raw) {
  if (is.na(list_raw)) return("US designation")
  if (grepl("1260H", list_raw, ignore.case = TRUE)) return("DoD 1260H")
  if (grepl("Footnote 4", list_raw, ignore.case = TRUE)) return("Entity List · FN4")
  "Entity List (BIS)"
}

# ---- All US-designated entities across the three data files ----
load_designations <- function(fac_path = "data/facilities.yml", des_path = "data/design.yml", mat_path = "data/materials.yml") {
  rows <- list()
  fac <- yaml::read_yaml(fac_path)$facilities
  for (f in fac) {
    el <- f$entity_list
    if (isTRUE(el$status)) rows[[length(rows)+1]] <- tibble(
      id = f$id, name = f$name_en, kind = "Facility",
      sub = f$type, place = paste(f$location$city, f$location$province),
      date = as.Date(el$date_added %||% NA), list_raw = el$list %||% NA_character_,
      page = paste0("facilities/", f$id, ".html")
    )
  }
  des <- yaml::read_yaml(des_path)$design_firms
  for (f in des) {
    el <- f$entity_list
    if (isTRUE(el$status)) rows[[length(rows)+1]] <- tibble(
      id = f$id, name = f$name_en, kind = "Design firm",
      sub = f$category, place = paste(f$location$city, f$location$province),
      date = as.Date(el$date_added %||% NA), list_raw = el$list %||% NA_character_,
      page = paste0("design-firms/", f$id, ".html")
    )
  }
  mat <- yaml::read_yaml(mat_path)$materials_firms
  for (f in mat) {
    el <- f$entity_list
    if (isTRUE(el$status)) rows[[length(rows)+1]] <- tibble(
      id = f$id, name = f$name_en, kind = "Equipment & materials",
      sub = f$segment, place = f$hq$city,
      date = as.Date(el$date_added %||% NA), list_raw = el$list %||% NA_character_,
      page = paste0("equipment-firms/", f$id, ".html")
    )
  }
  bind_rows(rows) %>%
    mutate(designation = sapply(list_raw, designation_label)) %>%
    arrange(date)
}

# ---- Stop hard on a duplicate id within one entity file. A duplicate id
# would make its generator overwrite one entry's generated profile page
# with another's, silently. Called by every loader before building rows. ----
stop_on_duplicate_ids <- function(entries, file_label) {
  ids <- sapply(entries, function(e) e$id)
  if (any(duplicated(ids))) {
    stop("Duplicate id(s) found in ", file_label, ": ", paste(unique(ids[duplicated(ids)]), collapse = ", "))
  }
}

# ---- Load China's boundary CLIPPED of India's officially claimed territory,
# and India's own official boundary, for every map on this site. Never draw
# the raw (unclipped) China polygon: ne_countries()'s China boundary overlaps
# India's DataMeet boundary by ~41,000 sq km (Aksai Chin, Shaksgam valley) —
# an opaque China outline drawn over that area would depict Indian territory
# as Chinese even with India's layer added on top afterward. Clipping first
# removes the China polygon from that area entirely, so there is nothing left
# for China's stroke to outline there. Requires library(sf) and
# library(rnaturalearth) loaded by the caller. ----
load_boundaries <- function() {
  china_raw <- rnaturalearth::ne_countries(country = "China", scale = "medium", returnclass = "sf")
  india <- sf::st_read("data/shp/datameet/india-composite.geojson", quiet = TRUE)

  china_v <- sf::st_make_valid(china_raw)
  india_v <- sf::st_make_valid(india)
  china_clipped <- sf::st_make_valid(sf::st_difference(china_v, sf::st_union(india_v)))

  list(china = china_clipped, india = india_v)
}

# ---- Add the clipped China boundary + India's official boundary to a
# leaflet map, India always drawn last (on top). ----
add_boundary_layers <- function(map, boundaries) {
  map %>%
    leaflet::addPolygons(
      data = boundaries$china,
      color = "#620d3c", weight = 2, fillColor = "#E8EAF0", fillOpacity = 0.1,
      group = "China Boundary"
    ) %>%
    leaflet::addPolygons(
      data = boundaries$india,
      color = "#1565C0", weight = 2, fillColor = "#D6E4F0", fillOpacity = 0.25,
      group = "India (Official Boundary)"
    )
}

# ---- Load and flatten facilities YAML into a tibble ----
load_facilities <- function(path = "data/facilities.yml") {
  raw <- yaml::read_yaml(path)
  stop_on_duplicate_ids(raw$facilities, path)

  rows <- lapply(raw$facilities, function(f) {
    trajectory <- f$node_trajectory
    current_node <- if (length(trajectory) > 0) {
      trajectory[[length(trajectory)]]$node
    } else {
      NA_character_
    }

    # Latest milestone date: used as the end of a cancelled project's
    # timeline bar (the last thing that happened to it), so the bar does not
    # run on to today as if the project were still under way.
    milestone_dates <- as.Date(vapply(f$milestones %||% list(), function(m) as.character(m$date), character(1)))
    last_milestone <- if (length(milestone_dates) > 0) max(milestone_dates) else as.Date(NA)

    # Latest source date: shown on profile pages as a freshness signal when
    # no explicit last_verified date has been recorded.
    source_dates <- as.Date(vapply(f$sources %||% list(), function(s) as.character(s$date), character(1)))
    latest_source <- if (length(source_dates) > 0) max(source_dates) else as.Date(NA)

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
      capacity_wpm          = f$capacity$wafers_per_month %||% NA_real_,
      capacity_units_pm     = f$capacity$units_per_month %||% NA_real_,
      capacity_wafer_size   = f$capacity$wafer_size %||% NA_character_,
      capacity_basis        = f$capacity$basis %||% NA_character_,
      capacity_as_of        = as.character(f$capacity$as_of %||% NA_character_),
      capacity_source       = f$capacity$note %||% NA_character_,
      last_verified         = as.Date(f$last_verified %||% NA),
      latest_source_date    = latest_source,
      last_milestone_date   = last_milestone,
      equipment_assessed    = !is.null(f$equipment_origin$domestic_pct) || isTRUE(f$equipment_origin$smuggled_flagged) || length(f$equipment_origin$key_foreign_tools) > 0,
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

# ---- Facilities that count toward headline totals. Cancelled projects stay
# on the site (they are part of the story) but their announced investment was
# never spent, so they are excluded from every "disclosed investment" sum. ----
active_facilities <- function(df) {
  df %>% filter(status != "Cancelled")
}

# ---- Delete generated profile pages whose id no longer exists in the YAML
# (e.g. after an id is renamed). Without this, Quarto keeps rendering the
# orphaned page and it stays live on the site. ----
remove_orphan_pages <- function(dir, ids) {
  existing <- list.files(dir, pattern = "\\.qmd$")
  orphans <- setdiff(existing, paste0(ids, ".qmd"))
  if (length(orphans) > 0) {
    file.remove(file.path(dir, orphans))
    cat("Removed orphaned pages:", paste(orphans, collapse = ", "), "\n")
  }
}

# ---- Format a raw YAML capacity block for display. Works for all three
# kinds of entry: fabs (wafers_per_month), OSAT sites (units_per_month), and
# equipment/materials firms (amount + unit). Returns "Not yet recorded" when
# nothing usable is present. ----
format_capacity <- function(cap) {
  if (is.null(cap)) return("Not yet recorded")
  fmt <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
  main <- if (!is.null(cap$wafers_per_month)) {
    size <- if (!is.null(cap$wafer_size)) paste0(" (", cap$wafer_size, ")") else ""
    paste0(fmt(cap$wafers_per_month), " wafers/month", size)
  } else if (!is.null(cap$units_per_month)) {
    paste0(fmt(cap$units_per_month), " units/month")
  } else if (!is.null(cap$amount) && !is.null(cap$unit)) {
    paste(fmt(cap$amount), cap$unit)
  } else {
    return("Not yet recorded")
  }
  # A planned or full-build target is labelled as such, so it is never
  # read as output that is actually running
  if (identical(cap$basis, "planned")) main <- paste0("Planned: ", main)
  as_of <- if (!is.null(cap$as_of)) paste0(", as of ", cap$as_of) else ""
  note <- if (!is.null(cap$note)) paste0(" — ", cap$note) else ""
  paste0(main, as_of, note)
}

# ---- Render a dated trajectory list (node / packaging / capability) as
# Markdown bullets. `field` names the text field in each entry. ----
trajectory_md <- function(entries, field, empty_text) {
  if (is.null(entries) || length(entries) == 0) return(empty_text)
  paste(vapply(entries, function(t) paste0("- **", t$year, "**: ", t[[field]]), character(1)), collapse = "\n")
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

# ---- Map ownership category to marker colour ----
category_color <- function(category) {
  switch(category,
    "State-Backed"      = "#620d3c",
    "Private"           = "#2f6b6b",
    "JV"                = "#6A1B9A",
    "Foreign-Invested"  = "#1565C0",
    "#757575"
  )
}

# ---- Map facility type to marker colour (matches the India tracker's
# Fab/Assembly & Packaging/Compound Semiconductor/Research Fab palette,
# plus Memory for this site's memory-maker entries) ----
type_color <- function(type) {
  switch(type,
    "Fab"                    = "#620d3c",
    "Assembly & Packaging"   = "#2f6b6b",
    "Memory"                 = "#1565C0",
    "Compound Semiconductor" = "#6A1B9A",
    "Research Fab"           = "#455A64",
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
  # Escape the tooltip text so a quote or angle bracket in status_detail
  # cannot break the surrounding HTML attribute.
  title_attr <- if (nchar(detail) > 0) paste0(' title="', htmltools::htmlEscape(detail, attribute = TRUE), '"') else ""
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

# ---- Render a US-designation badge (empty string if not flagged). Labels
# by which list actually applies — "Entity List" (Commerce/BIS export
# restrictions) and "DoD 1260H" (a legally distinct Defense Department
# military-company designation) are not interchangeable, and a badge that
# always says "Entity List" would misdescribe a 1260H-only entry. ----
entity_list_badge_html <- function(flagged, date_added = NA, list_name = NA_character_) {
  if (!isTRUE(flagged)) return("")
  is_1260h <- !is.na(list_name) && grepl("1260H", list_name, ignore.case = TRUE)
  label <- if (is_1260h) "⚠ DoD 1260H" else "⚠ Entity List"
  detail <- if (!is.na(date_added)) {
    paste0(" (added ", format(date_added, "%b %Y"), ", ", list_name, ")")
  } else ""
  glue('<span class="status-badge badge-cancelled" title="{label}{detail}">{label}</span>')
}

# ---- Build the Chinese-name subtitle line, gracefully empty if unverified ----
zh_name_line <- function(name_zh, name_pinyin) {
  if (is.na(name_zh) || is.na(name_pinyin) || nchar(name_zh) == 0) return("")
  glue('<span class="zh-name">{name_zh} · {name_pinyin}</span><br/>')
}

# ---- Build leaflet popup HTML ----
# Popups are an overview, not the full story: long prose fields are clipped
# at a word boundary so the popup fits the viewport (paired with maxHeight in
# popupOptions); the "Full Profile" link carries the reader to everything.
truncate_text <- function(s, max_chars = 260) {
  if (is.na(s) || nchar(s) <= max_chars) return(s)
  cut_at <- if (grepl("[.!?] ", substr(s, 1, max_chars))) {
    m <- gregexpr("[.!?] ", substr(s, 1, max_chars))[[1]]
    if (length(m) > 0) max(m) + 1 else max_chars
  } else {
    w <- gregexpr("\\s", substr(s, 1, max_chars))[[1]]
    if (length(w) > 0) max(w) - 1 else max_chars
  }
  paste0(substr(s, 1, cut_at), " …")
}

make_popup <- function(row) {
  sig_html <- if (nchar(row$significance) > 0) {
    glue('<div class="popup-significance">{truncate_text(row$significance, 280)}</div>')
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
  stop_on_duplicate_ids(raw$design_firms, path)

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
      latest_source_date = max_source_date(f$sources),
      n_sources         = length(f$sources %||% list()),
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
      <div class="popup-row"><span class="popup-label">Focus:</span> {truncate_text(row$product_focus, 160)}</div>
      <div class="popup-row"><span class="popup-label">Node:</span> {truncate_text(row$node_sophistication, 200)}</div>
      <div class="popup-row">{entity_list_badge_html(row$entity_list_flagged, row$entity_list_date, row$entity_list_name)}</div>
      <div class="popup-row" style="margin-top:6px;"><a href="design-firms/{row$id}.html" class="btn-detail">Full Profile →</a></div>
    </div>
  ')
}

# ---- Load and flatten equipment/materials YAML into a tibble ----
load_materials_firms <- function(path = "data/materials.yml") {
  raw <- yaml::read_yaml(path)
  stop_on_duplicate_ids(raw$materials_firms, path)

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
      what_it_supplies = f$narrative$what_it_supplies %||% "",
      last_verified  = as.Date(f$last_verified %||% NA)
    )
  })

  df <- bind_rows(rows)
  set.seed(45)
  df %>% mutate(lat = lat + runif(n(), -0.015, 0.015), lon = lon + runif(n(), -0.015, 0.015))
}

segment_color <- function(segment) {
  # Firms often span several process families ("Etch, Deposition, CMP");
  # colour markers by the primary (first-listed) segment so multi-segment
  # firms don't fall through to the grey default.
  primary <- trimws(strsplit(segment, ",", fixed = TRUE)[[1]][1])
  switch(primary,
    "Lithography"     = "#620d3c",
    "Etch"            = "#1565C0",
    "Deposition"      = "#2f6b4a",
    "CMP"             = "#6A1B9A",
    "Photoresist"     = "#f1a222",
    "Specialty Gas"   = "#00796B",
    "Wafers"          = "#455A64",
    "Cleaning"        = "#8D6E63",
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
      <div class="popup-row"><span class="popup-label">Node capability:</span> {truncate_text(row$node_capability, 180)}</div>
      <div class="popup-row">{entity_list_badge_html(row$entity_list_flagged, row$entity_list_date, row$entity_list_name)}</div>
      <div class="popup-row" style="margin-top:6px;"><a href="equipment-firms/{row$id}.html" class="btn-detail">Full Profile →</a></div>
    </div>
  ')
}

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
