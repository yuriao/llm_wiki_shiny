# ============================================================
# wiki_io.R — 文件系统 IO、frontmatter 解析、目录树、wikilink 提取
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
# ============================================================

library(yaml)

# 页面分类目录（Karpathy 三层架构 Layer 2）
WIKI_DIRS <- c("entities", "concepts", "comparisons", "queries")

# 顶层文档（Layer 3 schema + 导航）
WIKI_TOP_DOCS <- c("SCHEMA.md", "index.md", "log.md")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# 相对路径（相对 wiki 根）
rel_path <- function(f, root) {
  r  <- normalizePath(root, mustWork = FALSE)
  f2 <- normalizePath(f, mustWork = FALSE)
  if (startsWith(f2, r)) substr(f2, nchar(r) + 2, nchar(f2)) else f2
}

# ---- frontmatter ----

# 解析 YAML frontmatter（--- ... --- 开头块）
parse_frontmatter <- function(content) {
  if (!startsWith(content, "---")) return(list(fm = list(), body = content))
  lines <- strsplit(content, "\n", fixed = TRUE)[[1]]
  # 找第二个 ---（第一个在行 1）
  end_idx <- which(lines[-1] == "---")
  if (length(end_idx) == 0) return(list(fm = list(), body = content))
  end <- end_idx[1] + 1
  fm_text <- paste(lines[2:(end - 1)], collapse = "\n")
  body    <- paste(lines[(end + 1):length(lines)], collapse = "\n")
  fm <- tryCatch(yaml.load(fm_text), error = function(e) list())
  if (is.null(fm)) fm <- list()
  list(fm = fm, body = body)
}

# ---- 页面读写 ----

read_wiki_page <- function(path) {
  content <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  p <- parse_frontmatter(content)
  list(
    path        = path,
    title       = p$fm$title %||% tools::file_path_sans_ext(basename(path)),
    frontmatter = p$fm,
    body        = p$body,
    raw         = content
  )
}

write_wiki_page <- function(path, frontmatter, body) {
  fm_text <- if (length(frontmatter) > 0) {
    paste0("---\n", as.yaml(frontmatter), "---\n")
  } else ""
  writeLines(paste0(fm_text, body), path, useBytes = TRUE)
  invisible(TRUE)
}

# ---- 扫描 ----

# 所有 wiki 页面（四类目录下），返回 data.frame
list_wiki_pages <- function(wiki_root) {
  if (!dir.exists(wiki_root)) return(data.frame())
  files <- list.files(wiki_root, pattern = "\\.md$",
                      recursive = TRUE, full.names = TRUE)
  keep <- vapply(files, function(f) {
    d1 <- strsplit(rel_path(f, wiki_root), "/", fixed = TRUE)[[1]][1]
    d1 %in% WIKI_DIRS
  }, logical(1))
  files <- files[keep]
  if (length(files) == 0) return(data.frame())
  out <- lapply(files, function(f) {
    page <- read_wiki_page(f)
    rel  <- rel_path(f, wiki_root)
    data.frame(
      path    = f,
      relpath = rel,
      title   = page$title,
      type    = strsplit(rel, "/", fixed = TRUE)[[1]][1],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

# 顶层文档路径
top_doc_path <- function(wiki_root, name) {
  p <- file.path(wiki_root, name)
  if (file.exists(p)) p else NULL
}

# 目录树（shinyTree 兼容的嵌套命名 list；叶子为 character(0)）
build_tree_data <- function(wiki_root) {
  if (!dir.exists(wiki_root)) return(list())
  tree <- list()
  # 顶层文档
  for (doc in WIKI_TOP_DOCS) {
    p <- top_doc_path(wiki_root, doc)
    if (!is.null(p)) tree[[doc]] <- list(`#` = paste0("doc::", p))
  }
  # 分类目录
  for (d in WIKI_DIRS) {
    dirp <- file.path(wiki_root, d)
    if (!dir.exists(dirp)) next
    files <- list.files(dirp, pattern = "\\.md$", full.names = TRUE, recursive = TRUE)
    if (length(files) == 0) { tree[[d]] <- list(`#` = "empty"); next }
    sub <- list()
    for (f in files) {
      page <- read_wiki_page(f)
      nm   <- page$title %||% tools::file_path_sans_ext(basename(f))
      sub[[paste0(nm, " (", basename(f), ")")]] <- list(`#` = paste0("page::", f))
    }
    tree[[d]] <- sub
  }
  # raw/ 目录
  rawp <- file.path(wiki_root, "raw")
  if (dir.exists(rawp)) {
    raw_files <- list.files(rawp, full.names = TRUE, recursive = TRUE)
    if (length(raw_files) > 0) {
      raws <- list()
      for (f in raw_files) raws[[basename(f)]] <- list(`#` = paste0("raw::", f))
      tree[["raw"]] <- raws
    }
  }
  tree
}

# ---- wikilinks ----

# 提取 [[目标]] 或 [[目标|显示名]]
extract_wikilinks <- function(text) {
  m <- regmatches(text, gregexpr("\\[\\[[^\\[\\]\\n]+\\]\\]", text, perl = TRUE))[[1]]
  if (length(m) == 0) return(character(0))
  vapply(m, function(x) {
    inner <- substr(x, 3, nchar(x) - 2)
    sub("\\|.*$", "", inner)
  }, character(1))
}
