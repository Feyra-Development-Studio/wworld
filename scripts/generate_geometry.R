#!/usr/bin/env Rscript
# scripts/generate_geometry.R
# Simple R stub for geometry generation used by the Pascal integration.

args <- commandArgs(trailingOnly = TRUE)
input <- NULL
output <- 'geometry.json'
if (length(args) > 0) {
  for (i in seq_along(args)) {
    if (args[i] == '--in' && (i+1) <= length(args)) input <- args[i+1]
    if (args[i] == '--out' && (i+1) <= length(args)) output <- args[i+1]
  }
}

# Read request.json if provided (optional)
if (!is.null(input) && file.exists(input)) {
  req <- jsonlite::fromJSON(input)
} else {
  req <- list(meta = list(level = 1, seed = 12345))
}

# Minimal geometry: empty arrays but valid structure
geo <- list(
  meta = list(level = req$meta$level, seed = req$meta$seed, generated = as.character(Sys.time())),
  rooms = list(),
  corridors = list(),
  adjacency = list()
)

jsonlite::write_json(geo, output, auto_unbox = TRUE, pretty = TRUE)
cat('Wrote', output, '\n')
