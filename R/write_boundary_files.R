# Serialize the map boundary geometries — the exact same objects
# load_boundaries() feeds the leaflet widgets today — to GeoJSON files in
# data/boundaries/, so the boundary layers can be fetched at runtime instead
# of being pasted into every map page (they pushed index.html to ~7 MB, over
# LinkedIn's 3 MB preview ceiling).
#
# Geometry is NOT simplified: coordinates keep full precision (17 decimals —
# lossless for the doubles sf carries). Visual output must stay identical to
# the inline layers; only the delivery changes.
#
# Run: Rscript R/write_boundary_files.R
source("R/helpers.R")
library(sf)

dir.create("data/boundaries", showWarnings = FALSE)
b <- load_boundaries()

st_write(b$china, "data/boundaries/china-clipped.geojson",
         driver = "GeoJSON", quiet = TRUE,
         options = c("COORD_PRECISION=17"))
st_write(b$india, "data/boundaries/india.geojson",
         driver = "GeoJSON", quiet = TRUE,
         options = c("COORD_PRECISION=17"))

cat("china-clipped:", format(file.size("data/boundaries/china-clipped.geojson"), big.mark = ","), "bytes\n")
cat("india:       ", format(file.size("data/boundaries/india.geojson"), big.mark = ","), "bytes\n")
