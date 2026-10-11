# R script to export the tracker's data as CSV and JSON downloads
# Run: Rscript R/export_data.R
#
# Writes to downloads/, which Quarto copies into the built site (see
# `resources` in _quarto.yml). The CSVs are flat, one row per entry, for
# spreadsheets; the JSON files keep each entry's full nested record
# (milestones, sources, node history) exactly as in the YAML.
source("R/helpers.R")
library(yaml)
library(jsonlite)

if (!dir.exists("downloads")) dir.create("downloads")

# ---- Helper: write a UTF-8 CSV (keeps Chinese names intact in Excel) ----
write_utf8_csv <- function(df, path) {
  # The BOM at the start tells Excel the file is UTF-8, so 中文 names
  # display correctly instead of as garbled characters.
  con <- file(path, open = "wb")
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  close(con)
  suppressWarnings(write.table(df, path, sep = ",", row.names = FALSE, na = "",
                               append = TRUE, qmethod = "double", fileEncoding = "UTF-8"))
}

# ---- Helper: write a JSON file with a licence/attribution header ----
write_json_export <- function(records, key, path) {
  out <- list(
    licence = "CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/",
    attribution = "China Semiconductor Tracker, Takshashila Institution (https://fabs-china.pranaykotas.com)",
    exported = format(Sys.Date()),
    records = records
  )
  names(out)[names(out) == "records"] <- key
  jsonlite::write_json(out, path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}

# ---- Facilities: flat CSV ----
# Drop the map-only columns (lat/lon here are jittered for display, so the
# exact YAML coordinates are re-read below) and internal helper columns.
raw_facs <- yaml::read_yaml("data/facilities.yml")$facilities
facilities <- load_facilities("data/facilities.yml") %>%
  select(-lat, -lon, -equipment_assessed, -last_milestone_date, -complexity_foreign) %>%
  mutate(
    lat = vapply(raw_facs, function(f) f$location$lat, numeric(1)),
    lon = vapply(raw_facs, function(f) f$location$lon, numeric(1))
  )
write_utf8_csv(facilities, "downloads/facilities.csv")

# ---- Facility milestones: one row per milestone ----
milestones <- bind_rows(lapply(raw_facs, function(f) {
  bind_rows(lapply(f$milestones %||% list(), function(m) {
    tibble(facility_id = f$id, facility = f$name_en, date = as.character(m$date), event = m$event)
  }))
}))
write_utf8_csv(milestones, "downloads/facility-milestones.csv")

# ---- Design firms and equipment/materials firms: flat CSVs ----
raw_design <- yaml::read_yaml("data/design.yml")$design_firms
design <- load_design_firms("data/design.yml") %>%
  mutate(
    lat = vapply(raw_design, function(f) f$location$lat, numeric(1)),
    lon = vapply(raw_design, function(f) f$location$lon, numeric(1))
  )
write_utf8_csv(design, "downloads/design-firms.csv")

raw_materials <- yaml::read_yaml("data/materials.yml")$materials_firms
materials <- load_materials_firms("data/materials.yml") %>%
  mutate(
    lat = vapply(raw_materials, function(f) f$hq$lat, numeric(1)),
    lon = vapply(raw_materials, function(f) f$hq$lon, numeric(1))
  )
write_utf8_csv(materials, "downloads/materials-firms.csv")

# ---- All sources across all three datasets: one row per citation ----
source_rows <- function(entries, kind) {
  bind_rows(lapply(entries, function(e) {
    bind_rows(lapply(e$sources %||% list(), function(s) {
      tibble(entry_type = kind, entry_id = e$id, entry = e$name_en,
             title = s$title %||% NA_character_, url = s$url, date = as.character(s$date %||% NA))
    }))
  }))
}
sources <- bind_rows(
  source_rows(raw_facs, "Facility"),
  source_rows(raw_design, "Design firm"),
  source_rows(raw_materials, "Equipment/materials firm")
)
write_utf8_csv(sources, "downloads/sources.csv")

# ---- Full nested JSON, straight from the YAML ----
write_json_export(raw_facs, "facilities", "downloads/facilities.json")
write_json_export(raw_design, "design_firms", "downloads/design-firms.json")
write_json_export(raw_materials, "materials_firms", "downloads/materials-firms.json")

cat("Exported", nrow(facilities), "facilities,", nrow(design), "design firms,",
    nrow(materials), "equipment/materials firms, and", nrow(sources), "sources to downloads/.\n")
