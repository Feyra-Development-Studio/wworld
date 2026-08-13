#!/usr/bin/env Rscript
# wworld: независимая проверка выгруженных подземелий.
#
# Скрипт ничего не генерирует. Он читает CSV, разложенные генератором на
# Pascal, и заново, своими средствами (матрицы и векторные операции R)
# проверяет инварианты:
#   1. связность: все проходимые клетки этажа образуют одну компоненту;
#   2. отсутствие наложений: любое соседство двух разных структур
#      зарегистрировано как запланированная связь, комнаты не слипаются;
#   3. каждая проходимая клетка принадлежит ровно одной структуре;
#   4. ранг коридора не выше разблокированного на этаже и соответствует
#      наибольшей из связываемых комнат;
#   5. длина коридора не больше удвоенной большей стороны большей из
#      связываемых комнат;
#   6. размеры комнат не выходят за лимиты прогрессии этажа.
#
# Правила прогрессии продублированы здесь намеренно: проверка должна быть
# независимой от реализации на Pascal, иначе она проверяет сама себя.
#
# Только ООП: вся логика — методы reference-классов.

suppressWarnings(suppressMessages(library(methods)))

WwRules <- setRefClass(
  "WwRules",
  fields = list(level = "numeric"),
  methods = list(
    maxRank = function() {
      if (level <= 2) return(1)
      if (level <= 5) return(2)
      3
    },
    allowComposite = function() level >= 8,
    maxSide = function(kind) {
      mx <- c(small = 5, medium = 8, large = 10)
      if (level >= 6) {
        for (l in 6:level) {
          slot <- (l - 6) %% 6
          if (slot %in% c(0, 2, 4)) mx["large"] <- mx["large"] + 1
          else if (slot %in% c(1, 3)) mx["medium"] <- mx["medium"] + 1
          else mx["small"] <- mx["small"] + 1
        }
      }
      unname(mx[kind])
    },
    rankFor = function(kind) {
      switch(kind, small = 1, medium = 2, large = 3)
    }
  )
)

WwLevel <- setRefClass(
  "WwLevel",
  fields = list(
    number = "numeric",
    code = "matrix",
    owner = "matrix",
    rooms = "data.frame",
    corridors = "data.frame",
    links = "data.frame",
    rules = "ANY"
  ),
  methods = list(
    initialize = function(...) {
      initFields(...)
      if (length(number) > 0) rules <<- WwRules$new(level = number)
      invisible(.self)
    },

    walkable = function() code >= 2 & code <= 9,

    # ---- матричный сдвиг: основа всех проверок соседства ----
    shifted = function(m, dx, dy, fill) {
      nr <- nrow(m); nc <- ncol(m)
      out <- matrix(fill, nr, nc)
      rs <- max(1, 1 - dy):min(nr, nr - dy)
      cs <- max(1, 1 - dx):min(nc, nc - dx)
      out[rs, cs] <- m[rs + dy, cs + dx]
      out
    },

    # ---- 1. связность: заливка расширением по 8 направлениям ----
    componentCount = function() {
      walk <- walkable()
      if (!any(walk)) return(0)
      seen <- matrix(FALSE, nrow(code), ncol(code))
      idx <- which(walk)[1]
      seen[idx] <- TRUE
      repeat {
        grown <- seen
        for (dy in -1:1) for (dx in -1:1) {
          if (dx == 0 && dy == 0) next
          grown <- grown | shifted(seen, dx, dy, FALSE)
        }
        grown <- grown & walk
        if (identical(grown, seen)) break
        seen <- grown
      }
      if (sum(seen) == sum(walk)) 1 else 2
    },

    orphanCells = function() sum(walkable() & owner < 1),

    # ---- 2. все соседства разных структур ----
    adjacentPairs = function() {
      res <- NULL
      for (dy in -1:1) for (dx in -1:1) {
        if (dx == 0 && dy == 0) next
        a <- owner
        b <- shifted(owner, dx, dy, -1L)
        m <- a > 0 & b > 0 & a != b
        if (any(m)) {
          res <- rbind(res, cbind(pmin(a[m], b[m]), pmax(a[m], b[m])))
        }
      }
      if (is.null(res)) return(data.frame(a = integer(0), b = integer(0)))
      res <- unique(res)
      data.frame(a = res[, 1], b = res[, 2])
    },

    kindOf = function(id) {
      r <- rooms[rooms$id == id, ]
      if (nrow(r) > 0) return(as.character(r$kind[1]))
      c <- corridors[corridors$id == id, ]
      if (nrow(c) > 0) return("corridor")
      "fork"
    },

    linkRegistered = function(a, b) {
      any((links$a == a & links$b == b) | (links$a == b & links$b == a))
    },

    unplannedTouches = function() {
      pairs <- adjacentPairs()
      if (nrow(pairs) == 0) return(pairs[0, ])
      # метод передаётся обёрткой, а не по имени: анализатор кода
      # reference-классов видит только явные вызовы и иначе не установит
      # метод в объект (см. также kindOf ниже)
      bad <- !mapply(function(x, y) linkRegistered(x, y), pairs$a, pairs$b)
      pairs[bad, , drop = FALSE]
    },

    stuckRooms = function() {
      pairs <- adjacentPairs()
      if (nrow(pairs) == 0) return(pairs[0, ])
      ka <- vapply(pairs$a, function(id) kindOf(id), character(1))
      kb <- vapply(pairs$b, function(id) kindOf(id), character(1))
      pairs[ka %in% c("small", "medium", "large") &
            kb %in% c("small", "medium", "large"), , drop = FALSE]
    },

    # ---- 4-5. коридоры ----
    corridorProblems = function() {
      out <- character(0)
      if (nrow(corridors) == 0) return(out)
      for (i in seq_len(nrow(corridors))) {
        cr <- corridors[i, ]
        if (cr$rank > rules$maxRank()) {
          out <- c(out, sprintf("коридор %d: ранг %d выше разблокированного (%d)",
                                cr$id, cr$rank, rules$maxRank()))
        }
        ends <- c(cr$from_id, cr$to_id)
        er <- rooms[rooms$id %in% ends, ]
        if (nrow(er) > 0) {
          want <- min(max(vapply(as.character(er$kind),
                                 function(k) rules$rankFor(k), numeric(1))),
                      rules$maxRank())
          if (cr$rank != want) {
            out <- c(out, sprintf("коридор %d: ранг %d, ожидался %d по комнатам",
                                  cr$id, cr$rank, want))
          }
          limit <- 2 * max(er$size_metric)
          if (limit < 10) limit <- 10
          if (cr$path_len > limit) {
            out <- c(out, sprintf("коридор %d: длина %d > предела %d",
                                  cr$id, cr$path_len, limit))
          }
        }
      }
      out
    },

    # ---- 6. комнаты ----
    roomProblems = function() {
      out <- character(0)
      if (nrow(rooms) == 0) return(out)
      for (i in seq_len(nrow(rooms))) {
        rm <- rooms[i, ]
        lim <- rules$maxSide(as.character(rm$kind))
        if (rm$size_metric > lim) {
          out <- c(out, sprintf("комната %d (%s): размер %d > лимита %d",
                                rm$id, rm$kind, rm$size_metric, lim))
        }
        if (as.character(rm$shape) == "composite" && !rules$allowComposite()) {
          out <- c(out, sprintf("комната %d: составная форма на этаже %d",
                                rm$id, number))
        }
      }
      out
    }
  )
)

WwValidator <- setRefClass(
  "WwValidator",
  fields = list(dir = "character", failures = "numeric"),
  methods = list(
    initialize = function(...) {
      initFields(...)
      failures <<- 0
      invisible(.self)
    },

    path = function(f) file.path(dir, f),

    readMatrix = function(f) {
      as.matrix(read.csv(path(f), header = FALSE))
    },

    run = function() {
      idx <- read.csv(path("index.csv"), stringsAsFactors = FALSE)
      allRooms <- read.csv(path("rooms.csv"), stringsAsFactors = FALSE)
      allCor <- read.csv(path("corridors.csv"), stringsAsFactors = FALSE)
      allLinks <- read.csv(path("links.csv"), stringsAsFactors = FALSE)

      cat(sprintf("проверяю %d этажей из %s\n", nrow(idx), dir))
      for (i in seq_len(nrow(idx))) {
        row <- idx[i, ]
        lv <- WwLevel$new(
          number = row$level,
          code = readMatrix(row$sheet),
          owner = readMatrix(row$owner_sheet),
          rooms = allRooms[allRooms$level == row$level, ],
          corridors = allCor[allCor$level == row$level, ],
          links = allLinks[allLinks$level == row$level, ]
        )
        checkLevel(lv, row)
      }
      if (failures == 0) {
        cat("ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ\n")
        0
      } else {
        cat(sprintf("ОШИБОК: %d\n", failures))
        1
      }
    },

    report = function(level, ok, msg) {
      if (!ok) failures <<- failures + 1
      cat(sprintf("  [%s] эт.%2d %s\n", if (ok) "ok" else "СБОЙ", level, msg))
    },

    checkLevel = function(lv, row) {
      comp <- lv$componentCount()
      report(lv$number, comp == 1,
             sprintf("связность: компонент %d, проходимых клеток %d",
                     comp, sum(lv$walkable())))

      orph <- lv$orphanCells()
      report(lv$number, orph == 0,
             sprintf("владельцы: клеток без структуры %d", orph))

      touches <- lv$unplannedTouches()
      report(lv$number, nrow(touches) == 0,
             sprintf("незапланированных касаний: %d", nrow(touches)))

      stuck <- lv$stuckRooms()
      report(lv$number, nrow(stuck) == 0,
             sprintf("слипшихся комнат: %d", nrow(stuck)))

      cp <- lv$corridorProblems()
      report(lv$number, length(cp) == 0,
             sprintf("коридоры (%d шт.): замечаний %d%s", nrow(lv$corridors),
                     length(cp), if (length(cp)) paste0(" -> ", cp[1]) else ""))

      rp <- lv$roomProblems()
      report(lv$number, length(rp) == 0,
             sprintf("комнаты (%d шт.): замечаний %d%s", nrow(lv$rooms),
                     length(rp), if (length(rp)) paste0(" -> ", rp[1]) else ""))
    }
  )
)

WwMain <- setRefClass(
  "WwMain",
  fields = list(args = "character"),
  methods = list(
    dirArg = function() {
      i <- which(args == "--dir")
      if (length(i) && length(args) > i[1]) args[i[1] + 1] else "csv"
    },
    run = function() {
      v <- WwValidator$new(dir = dirArg())
      quit(status = v$run(), save = "no")
    }
  )
)

WwMain$new(args = commandArgs(trailingOnly = TRUE))$run()
