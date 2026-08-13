#!/usr/bin/env Rscript
# wworld: геометрия подземелья.
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
#   PING             -> OK PONG
#   QUIT             -> завершение
# Ошибка: ERR <текст>
#
# Только ООП: вся логика — методы reference-классов.

suppressWarnings(suppressMessages(library(methods)))

# setRefClass без пакета codetools сыплет предупреждениями в stderr —
# на протокол они не влияют, но засоряют лог CI
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
      list(mask = m, metric = sum(mapply(metric, types, ws, hs)))
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

WwGeometryServer <- suppressMessages(setRefClass(
  "WwGeometryServer",
  fields = list(shapes = "ANY", corridors = "ANY"),
  methods = list(

    initialize = function(...) {
      initFields(...)
      shapes <<- WwShapeFactory$new()
      corridors <<- WwCorridorGeometry$new()
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
