# ============================================================
# pdf_io.R — PDF 提取 → 虚拟 wiki 页面（供 llm_answer 上下文使用）
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
#
# 设计要点：返回结构与 read_wiki_page() 同构的 page-like 列表
# （list(path, title, frontmatter, body, raw)），因此可直接作为
# context_pages 传给 llm_answer()，llm_client.R 零改动。
# ============================================================

# 惰性加载 pdftools（避免 app 启动时强制依赖未装包）
.pdf_require <- function() {
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop("未安装 pdftools 包，请先运行：install.packages('pdftools')（需系统 poppler）")
  }
}

# PDF → 虚拟页面列表（按行分组切块，绝不切断句子）
# chunk_chars: 每块目标字符数（llm_answer 对单页 body 截 2000，块需小于该值）
# max_chunks:  上限块数，防止超大 PDF 撑爆 LLM 上下文
# 返回：page-like list，附加 attr "pdf_meta" = list(nchars, n_chunks, truncated)
# 失败：返回以 "❌" 开头的错误字符串（由 app.R 的 is_pdf_error 识别）
pdf_extract_pages <- function(pdf_path, chunk_chars = 1800, max_chunks = 24) {
  .pdf_require()
  if (!file.exists(pdf_path)) return(paste0("❌ PDF 文件不存在: ", pdf_path))

  txt <- tryCatch(
    paste(pdftools::pdf_text(pdf_path), collapse = "\n\n"),
    error = function(e) paste0("❌ PDF 解析失败：", conditionMessage(e))
  )
  if (startsWith(txt, "❌")) return(txt)

  # 文本清洗：压缩行内空白、多余空行
  txt <- gsub("[ \t]+", " ", txt)
  txt <- gsub("\n{3,}", "\n\n", txt)
  txt <- trimws(txt)

  nchars <- nchar(txt)
  if (nchars < 20) {
    return("❌ 未能从 PDF 提取到文本：可能是不含文本层的扫描件（暂不支持 OCR）")
  }

  # 按行累积切块（每块完整行，不切断句子/表格行）
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  chunks <- list()
  cur <- character(0)
  curlen <- 0L
  for (ln in lines) {
    if (curlen > 0L && curlen + nchar(ln) > chunk_chars) {
      chunks[[length(chunks) + 1L]] <- paste(cur, collapse = "\n")
      cur <- character(0)
      curlen <- 0L
    }
    cur <- c(cur, ln)
    curlen <- curlen + nchar(ln) + 1L
  }
  if (length(cur) > 0L) chunks[[length(chunks) + 1L]] <- paste(cur, collapse = "\n")

  total_needed <- ceiling(nchars / chunk_chars)
  truncated <- length(chunks) > max_chunks
  if (truncated) chunks <- chunks[seq_len(max_chunks)]
  n <- length(chunks)

  fname <- tools::file_path_sans_ext(basename(pdf_path))
  pages <- lapply(seq_len(n), function(i) {
    list(
      path        = pdf_path,
      title       = sprintf("PDF: %s（第 %d/%d 段）", fname, i, n),
      frontmatter = list(type = "pdf", source = basename(pdf_path)),
      body        = chunks[[i]],
      raw         = chunks[[i]]
    )
  })
  attr(pages, "pdf_meta") <- list(
    nchars    = nchars,
    n_chunks  = n,
    truncated = truncated || n < total_needed
  )
  pages
}

# 判断 pdf_extract_pages 返回值是否为错误字符串
is_pdf_error <- function(x) is.character(x)
