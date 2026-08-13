#!/usr/bin/env Rscript
# wworld: геометрия и топология подземелья.
#
# Скрипт запускается генератором на Pascal один раз и живёт всё время
# генерации, отвечая на запросы построчно через stdin/stdout. Вся геометрия
# считается здесь: комната — логическая матрица-маска, коридор — вектор
# клеток, кисть — вектор смещений. Pascal хранит сетку и занятость, но форм
# сам не строит.
#
# Случайности здесь нет и быть не должно: все ответы — чистые функции своих
# аргументов, а розыгрыш размеров и смещений остаётся за ГПСЧ на Pascal.
# Только так генерация воспроизводится по seed.
#
# Протокол (одна строка — один запрос):
#   SHAPE rect W H | SHAPE square S | SHAPE ellipse W H | SHAPE circle D
#       -> OK W H METRIC <маска 0/1, по строкам>
#   COMPOSITE N t w h ox oy [t w h ox oy ...]
#       -> OK W H METRIC <маска>        (bbox нормализуется, METRIC — сумма
#                                        длинных сторон/диаметров частей)
#   BRUSH R          -> OK N dx dy dx dy ...
#   EXPAND R N x y x y ...  -> OK M x y x y ...   (клетки коридора, без повторов)
#   WALLS W H <коды одной строкой цифр>
#       -> OK <коды со стенами>
#   FINALIZE W H SX SY <коды>
#       -> OK <достижимо> <всего> <x0> <y0> <x1> <y1> <коды со стенами>
#           достижимо/всего — охват заливки от (SX,SY) по проходимым клеткам,
#           x0..y1 — рамка непустой части с полем в клетку
#   PING             -> OK PONG
#   QUIT             -> завершение
# Ошибка: ERR <текст>
#
# Только ООП: вся логика — методы reference-классов.

suppressWarnings(suppressMessages(library(methods)))

# Без пакета codetools setRefClass сыплет предупреждениями в stderr: на
# протокол они не влияют, но засоряют лог. CI ставит codetools явно —
# он не только убирает шум, но и включает анализ кода классов.
options(warn = -1)

WwShapeFactory <- suppressMessages(setRefClass(
  "WwShapeFactory",
  methods = list(

    # прямоугольник: сплошная матрица
    rect = function(w, h) matrix(TRUE, nrow = h, ncol = w),

    # эллипс/круг: одно векторное выражение вместо двойного цикла
    ellipse = function(w, h) {
      cx <- (w - 1) / 2
      cy <- (h - 1) / 2
      xs <- ((0:(w - 1)) - cx) / (w / 2)
      ys <- ((0:(h - 1)) - cy) / (h / 2)
      outer(ys^2, xs^2, "+") <= 1.02
    },

    make = function(type, w, h) {
      switch(type,
        rect = rect(w, h),
        square = rect(w, w),
        ellipse = ellipse(w, h),
        circle = ellipse(w, w),
        stop(sprintf("неизвестная форма: %s", type))
      )
    },

    metric = function(type, w, h) {
      if (type %in% c("square", "circle")) w else max(w, h)
    },

    # составная комната: части намеренно накладываются и считаются одной
    # комнатой; маска — поэлементное ИЛИ частей, размер — сумма их длинных
    # сторон и больших диаметров
    composite = function(types, ws, hs, oxs, oys) {
      hs2 <- ifelse(types %in% c("square", "circle"), ws, hs)
      oxs <- oxs - min(oxs)
      oys <- oys - min(oys)
      W <- max(oxs + ws)
      H <- max(oys + hs2)
      m <- matrix(FALSE, nrow = H, ncol = W)
      for (i in seq_along(types)) {
        part <- make(types[i], ws[i], hs[i])
        rows <- (oys[i] + 1):(oys[i] + nrow(part))
        cols <- (oxs[i] + 1):(oxs[i] + ncol(part))
        m[rows, cols] <- m[rows, cols] | part
      }
      # метод оборачивается, а не передаётся по имени: анализатор кода
      # reference-классов ставит в объект только явно вызываемые методы
      list(mask = m, metric = sum(mapply(function(t, w, h) metric(t, w, h),
                                         types, ws, hs)))
    }
  )
))

WwCorridorGeometry <- suppressMessages(setRefClass(
  "WwCorridorGeometry",
  methods = list(

    # кисть ранга: 1 -> одна клетка, 2 -> квадрат 2x2, 3 -> 3x3 с центром
    brush = function(rank) {
      if (rank <= 1) return(cbind(0L, 0L))
      if (rank == 2) {
        g <- expand.grid(dx = 0:1, dy = 0:1)
      } else {
        g <- expand.grid(dx = -1:1, dy = -1:1)
      }
      cbind(as.integer(g$dx), as.integer(g$dy))
    },

    # разворачивание осевой линии в вектор клеток: внешнее сложение
    # координат со смещениями кисти, затем снятие повторов
    expand = function(rank, xs, ys) {
      b <- brush(rank)
      cx <- as.vector(outer(xs, b[, 1], "+"))
      cy <- as.vector(outer(ys, b[, 2], "+"))
      keep <- !duplicated(cx * 100000L + cy)
      cbind(cx[keep], cy[keep])
    }
  )
))

# Карта целиком — это матрица, а стены, связность и рамка — операции над
# матрицей: сдвиг, поэлементное ИЛИ, сравнение. Ровно то, ради чего здесь R.
WwMapAnalysis <- suppressMessages(setRefClass(
  "WwMapAnalysis",
  methods = list(

    shifted = function(m, dx, dy, fill) {
      nr <- nrow(m); nc <- ncol(m)
      out <- matrix(fill, nr, nc)
      rs <- max(1, 1 - dy):min(nr, nr - dy)
      cs <- max(1, 1 - dx):min(nc, nc - dx)
      out[rs, cs] <- m[rs + dy, cs + dx]
      out
    },

    dilate8 = function(mask) {
      out <- mask
      for (dy in -1:1) for (dx in -1:1) {
        if (dx == 0 && dy == 0) next
        out <- out | shifted(mask, dx, dy, FALSE)
      }
      out
    },

    walkable = function(m) m >= 2 & m <= 9,

    # стена — монолит, касающийся прохода хотя бы углом
    walls = function(m) {
      m[m == 0 & dilate8(walkable(m))] <- 1
      m
    },

    # заливка расширением: сколько проходимых клеток достижимо от старта
    reached = function(m, sx, sy) {
      walk <- walkable(m)
      seen <- matrix(FALSE, nrow(m), ncol(m))
      if (sy + 1 > nrow(m) || sx + 1 > ncol(m)) return(0)
      seen[sy + 1, sx + 1] <- TRUE
      repeat {
        grown <- dilate8(seen) & walk
        if (identical(grown, seen)) break
        seen <- grown
      }
      sum(seen)
    },

    # рамка непустой части с полем в одну клетку
    bbox = function(m, margin) {
      idx <- which(m != 0, arr.ind = TRUE)
      if (nrow(idx) == 0) return(c(0, 0, ncol(m) - 1, nrow(m) - 1))
      c(max(0, min(idx[, 2]) - 1 - margin),
        max(0, min(idx[, 1]) - 1 - margin),
        min(ncol(m) - 1, max(idx[, 2]) - 1 + margin),
        min(nrow(m) - 1, max(idx[, 1]) - 1 + margin))
    }
  )
))

WwGeometryServer <- suppressMessages(setRefClass(
  "WwGeometryServer",
  fields = list(shapes = "ANY", corridors = "ANY", maps = "ANY"),
  methods = list(

    initialize = function(...) {
      initFields(...)
      shapes <<- WwShapeFactory$new()
      corridors <<- WwCorridorGeometry$new()
      maps <<- WwMapAnalysis$new()
      invisible(.self)
    },

    # маска отдаётся одной строкой из 0/1, по строкам сверху вниз
    packMask = function(m) paste(as.integer(t(m)), collapse = ""),

    packPairs = function(m) paste(as.vector(t(m)), collapse = " "),

    handleShape = function(a) {
      type <- a[2]
      if (type %in% c("square", "circle")) {
        w <- as.integer(a[3]); h <- w
      } else {
        w <- as.integer(a[3]); h <- as.integer(a[4])
      }
      m <- shapes$make(type, w, h)
      sprintf("OK %d %d %d %s", ncol(m), nrow(m),
              shapes$metric(type, w, h), packMask(m))
    },

    handleComposite = function(a) {
      n <- as.integer(a[2])
      idx <- 3:(2 + 5 * n)
      f <- matrix(a[idx], nrow = 5)
      res <- shapes$composite(
        types = f[1, ],
        ws = as.integer(f[2, ]),
        hs = as.integer(f[3, ]),
        oxs = as.integer(f[4, ]),
        oys = as.integer(f[5, ])
      )
      sprintf("OK %d %d %d %s", ncol(res$mask), nrow(res$mask),
              res$metric, packMask(res$mask))
    },

    # карта передаётся строкой цифр: коды клеток укладываются в 0..9
    unpackMap = function(w, h, digits) {
      matrix(as.integer(strsplit(digits, "")[[1]]), nrow = h, ncol = w, byrow = TRUE)
    },

    packMap = function(m) paste(as.integer(t(m)), collapse = ""),

    handleWalls = function(a) {
      m <- unpackMap(as.integer(a[2]), as.integer(a[3]), a[4])
      sprintf("OK %s", packMap(maps$walls(m)))
    },

    handleFinalize = function(a) {
      w <- as.integer(a[2]); h <- as.integer(a[3])
      sx <- as.integer(a[4]); sy <- as.integer(a[5])
      m <- unpackMap(w, h, a[6])
      reach <- maps$reached(m, sx, sy)
      total <- sum(maps$walkable(m))
      m <- maps$walls(m)
      b <- maps$bbox(m, 1)
      sprintf("OK %d %d %d %d %d %d %s", reach, total, b[1], b[2], b[3], b[4], packMap(m))
    },

    handleBrush = function(a) {
      b <- corridors$brush(as.integer(a[2]))
      sprintf("OK %d %s", nrow(b), packPairs(b))
    },

    handleExpand = function(a) {
      rank <- as.integer(a[2])
      n <- as.integer(a[3])
      v <- as.integer(a[4:(3 + 2 * n)])
      cells <- corridors$expand(rank, v[seq(1, length(v), by = 2)],
                                      v[seq(2, length(v), by = 2)])
      sprintf("OK %d %s", nrow(cells), packPairs(cells))
    },

    dispatch = function(line) {
      a <- strsplit(trimws(line), "[ \t]+")[[1]]
      if (length(a) == 0) return("ERR пустой запрос")
      switch(a[1],
        SHAPE = handleShape(a),
        COMPOSITE = handleComposite(a),
        BRUSH = handleBrush(a),
        WALLS = handleWalls(a),
        FINALIZE = handleFinalize(a),
        EXPAND = handleExpand(a),
        PING = "OK PONG",
        sprintf("ERR неизвестная команда: %s", a[1])
      )
    },

    run = function() {
      con <- file("stdin", "r")
      repeat {
        line <- readLines(con, n = 1)
        if (length(line) == 0) break
        if (trimws(line) == "QUIT") break
        out <- tryCatch(dispatch(line),
                        error = function(e) sprintf("ERR %s", conditionMessage(e)))
        cat(out, "\n", sep = "")
        flush(stdout())
      }
      invisible(NULL)
    }
  )
))

WwGeometryServer$new()$run()
