#!/usr/bin/env Rscript
# Эталонные ответы GNU R для сверки с Renjin.
# Скрипт грузится как библиотека и опрашивается через dispatch — ровно так,
# как это будет делать встроенный движок.
ww.embedded <- TRUE
args <- commandArgs(trailingOnly = TRUE)
source(args[1])
srv <- WwGeometryServer$new()
for (line in readLines(args[2])) {
  if (!nzchar(trimws(line))) next
  cat(srv$dispatch(line), "\n", sep = "")
}
