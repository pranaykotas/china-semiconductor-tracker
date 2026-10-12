# R script to generate OpenGraph/Twitter link-preview cards (1200x630 PNG)
# for every facility, design firm, and equipment/materials firm, plus a
# site-level default. Run: Rscript R/generate_social_cards.R
#
# Cards are ASCII/Latin-only (pinyin, not hanzi) so rendering is identical
# on any machine — they are generated locally and COMMITTED, not built in CI.
source("R/helpers.R")
library(sf)
library(rnaturalearth)
library(dplyr)
library(glue)
library(ragg)

W <- 1200; H <- 630
BG <- "#1B1B21"; PANEL <- "#620d3c"; INK <- "#F2EDE6"; MUTED <- "#A39B94"; DIM <- "#2C2C35"

boundaries <- load_boundaries()

canvas_setup <- function() {
  par(mar = c(0, 0, 0, 0), bg = BG, fg = INK)
  layout(matrix(c(1, 2), 1, 2), widths = c(1.4, 1))
}

draw_map <- function(points = NULL, highlight = NULL, accent = "#f1a222") {
  par(mar = c(0.2, 0, 0.2, 0.4))
  # st_geometry: plot a single map, not one subplot per attribute column.
  # India is not drawn — this is a China map; only the clipped China
  # silhouette (free of Indian claimed territory) appears.
  plot(sf::st_geometry(boundaries$china), col = DIM, border = "#4E3A45", axes = FALSE)
  if (!is.null(points) && nrow(points) > 0) {
    points(points$lon, points$lat, col = "#8C8480", pch = 16, cex = 0.55)
  }
  if (!is.null(highlight)) {
    points(highlight$lon, highlight$lat, col = accent, pch = 16, cex = 2.2)
    points(highlight$lon, highlight$lat, col = accent, pch = 1, lwd = 2, cex = 4)
  }
}

draw_text_panel <- function(kicker, name, subline, place_line, status_line) {
  plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
  rect(0, 0.955, 1, 1, col = PANEL, border = NA)
  text(0.05, 0.86, toupper(kicker), adj = 0, col = MUTED, cex = 0.95, font = 2)
  # wrap the name across at most 2 lines
  words <- strsplit(name, " ", fixed = TRUE)[[1]]
  title <- name
  if (nchar(name) > 26) {
    mid <- ceiling(length(words) / 2)
    title <- paste(c(head(words, mid), tail(words, length(words) - mid)), collapse = "\n")
  }
  text(0.05, 0.66, title, adj = c(0, 0.5), col = INK, cex = 3.4, font = 2)
  if (!is.null(subline) && nchar(subline) > 0) {
    text(0.05, 0.38, subline, adj = 0, col = "#D8CFBE", cex = 1.25)
  }
  if (!is.null(place_line) && nchar(place_line) > 0) {
    text(0.05, 0.29, place_line, adj = 0, col = MUTED, cex = 1.15)
  }
  if (!is.null(status_line) && nchar(status_line) > 0) {
    text(0.05, 0.20, status_line, adj = 0, col = "#C89A2B", cex = 1.1, font = 3)
  }
  text(0.05, 0.06, "China Semiconductor Tracker · fabs-china.pranaykotas.com",
       adj = 0, col = MUTED, cex = 0.95)
}

pinyin_or_blank <- function(p) ifelse(is.na(p) | p == "", "", p)

make_entity_card <- function(out, kicker, name, subline, place_line, status_line, accent, lat, lon, all_pts) {
  agg_png(out, W, H, units = "px", res = 96)
  canvas_setup()
  draw_text_panel(kicker, name, subline, place_line, status_line)
  draw_map(points = all_pts, highlight = data.frame(lat = lat, lon = lon), accent = accent)
  invisible(dev.off())
}

# ---- Assemble entities ---------------------------------------------------
facilities <- load_facilities("data/facilities.yml")
firms_des <- load_design_firms("data/design.yml")
firms_mat <- load_materials_firms("data/materials.yml")

all_pts <- bind_rows(
  facilities[, c("lat", "lon")],
  firms_des[, c("lat", "lon")],
  firms_mat[, c("lat", "lon")]
)

dir.create("images/cards", recursive = TRUE, showWarnings = FALSE)

# Facilities
for (i in seq_len(nrow(facilities))) {
  f <- facilities[i, ]
  make_entity_card(
    out = glue("images/cards/facility-{f$id}.png"),
    kicker = glue("Facility · {toupper(f$type)}"),
    name = f$name_en,
    subline = paste0(f$company_en, " · ", pinyin_or_blank(f$name_pinyin)),
    place_line = paste0(f$city, ", ", f$province),
    status_line = f$status,
    accent = type_color(f$type),
    lat = f$lat, lon = f$lon, all_pts = all_pts
  )
}
cat("Facility cards:", nrow(facilities), "\n")

# Design firms
for (i in seq_len(nrow(firms_des))) {
  f <- firms_des[i, ]
  status_line <- if (isTRUE(f$entity_list_flagged)) "US ENTITY LIST — BIS" else ""
  make_entity_card(
    out = glue("images/cards/design-{f$id}.png"),
    kicker = glue("Design firm · {toupper(f$category)}"),
    name = f$name_en,
    subline = pinyin_or_blank(f$name_pinyin),
    place_line = paste0(f$city, ", ", f$province),
    status_line = status_line,
    accent = design_category_color(f$category),
    lat = f$lat, lon = f$lon, all_pts = all_pts
  )
}
cat("Design cards:", nrow(firms_des), "\n")

# Equipment & materials firms
for (i in seq_len(nrow(firms_mat))) {
  f <- firms_mat[i, ]
  status_line <- if (isTRUE(f$entity_list_flagged)) "US ENTITY LIST — BIS" else ""
  make_entity_card(
    out = glue("images/cards/material-{f$id}.png"),
    kicker = glue("Equipment & Materials · {toupper(f$segment)}"),
    name = f$name_en,
    subline = pinyin_or_blank(f$name_pinyin),
    place_line = f$city,
    status_line = status_line,
    accent = segment_color(f$segment),
    lat = f$lat, lon = f$lon, all_pts = all_pts
  )
}
cat("Materials cards:", nrow(firms_mat), "\n")

# ---- Site-level default card: the whole footprint in one image -----------
agg_png("images/og-image.png", W, H, units = "px", res = 96)
canvas_setup()
draw_text_panel(
  "A Takshashila Research Project",
  "China Semiconductor Tracker",
  "Fabs · memory · OSAT · compound · design firms · equipment",
  glue("{nrow(facilities)} facilities · {nrow(firms_des)} design firms · {nrow(firms_mat)} equipment & materials firms"),
  ""
)
draw_map(points = all_pts, highlight = NULL)
invisible(dev.off())
cat("Site default card: images/og-image.png\n")
