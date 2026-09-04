# PDF IO 测试 — 验证 pdf_extract_pages 切块/错误路径/截断
# 用法: Rscript test_pdf_io.R （需 pdftools 包 + /usr/sbin/cupsfilter 生成样例）

cat("=== PDF IO 测试 ===\n")
for (f in c("wiki_io.R", "pdf_io.R"))
  sys.source(file.path("R", f), envir = globalenv())

if (!requireNamespace("pdftools", quietly = TRUE)) {
  cat("❌ pdftools 未安装，跳过全部测试\n"); quit(status = 1)
}
if (!file.exists("/usr/sbin/cupsfilter")) {
  cat("⚠️ cupsfilter 不可用，仅测试错误路径\n")
}

# 工具：文本 → PDF（cupsfilter，macOS 自带）
make_text_pdf <- function(txt, pdf_path) {
  src <- tempfile(fileext = ".txt")
  writeLines(txt, src)
  ok <- system2("/usr/sbin/cupsfilter", src, stdout = pdf_path, stderr = FALSE)
  unlink(src)
  stopifnot(ok == 0, file.exists(pdf_path), file.info(pdf_path)$size > 500)
  invisible(TRUE)
}

td <- tempfile("pdfio_"); dir.create(td)

cat("\n=== 1. 正常长文本：page-like 结构 + 多块切分 ===\n")
long_txt <- paste(sprintf("段落 %03d：注意力机制允许模型动态聚焦输入序列的关键部分，这是 Transformer 架构的核心创新之一。", 1:80), collapse = "\n")
pdf1 <- file.path(td, "long.pdf")
make_text_pdf(long_txt, pdf1)
pages <- pdf_extract_pages(pdf1)
stopifnot(!is_pdf_error(pages), is.list(pages))
meta <- attr(pages, "pdf_meta")
cat("字符数:", meta$nchars, "| 块数:", meta$n_chunks, "| 截断:", meta$truncated, "\n")
stopifnot(meta$n_chunks >= 2, !meta$truncated)
# page-like 结构完整（llm_answer 需要 title / frontmatter$type / body）
for (p in pages) {
  stopifnot(!is.null(p$title), !is.null(p$body),
            identical(p$frontmatter$type, "pdf"),
            nchar(p$body) < 2000)  # llm_answer 对单页截 2000，块必须更小
}
cat("首块标题:", pages[[1]]$title, "\n")
stopifnot(grepl("^PDF: long（第 1/", pages[[1]]$title, fixed = FALSE))
# 内容完整性：首块含开头、末块含结尾
stopifnot(grepl("段落 001", pages[[1]]$body, fixed = TRUE),
          grepl("段落 080", pages[[length(pages)]]$body, fixed = TRUE))

cat("\n=== 2. 短文本：单块 ===\n")
short_txt <- paste(sprintf("短文档第 %02d 节：RAG 是检索增强生成的缩写，与长文本场景配合测试。", 1:3), collapse = "\n")
pdf2 <- file.path(td, "short.pdf")
make_text_pdf(short_txt, pdf2)
p2 <- pdf_extract_pages(pdf2)
stopifnot(!is_pdf_error(p2), length(p2) == 1, nchar(p2[[1]]$body) > 10)
cat("块数:", length(p2), "| 提取字符:", nchar(p2[[1]]$body), "✅\n")

cat("\n=== 3. 超大文本：截断到 max_chunks ===\n")
huge_txt <- paste(sprintf("第 %03d 行填充内容，用于验证超大 PDF 的上下文上限保护机制是否生效。", 1:3000),
                  collapse = "\n")  # ~3000 行 × 40 字 ≈ 120K 字符
pdf3 <- file.path(td, "huge.pdf")
make_text_pdf(huge_txt, pdf3)
p3 <- pdf_extract_pages(pdf3)
m3 <- attr(p3, "pdf_meta")
cat("字符数:", m3$nchars, "| 块数:", m3$n_chunks, "| 截断:", m3$truncated, "\n")
stopifnot(m3$n_chunks == 24, isTRUE(m3$truncated), length(p3) == 24)

cat("\n=== 4. 不存在的文件 → 错误字符串 ===\n")
e1 <- pdf_extract_pages(file.path(td, "nope.pdf"))
stopifnot(is_pdf_error(e1), grepl("❌", e1, fixed = TRUE))
cat(e1, "\n✅\n")

cat("\n=== 5. 无文本层 PDF（纯图形）→ 扫描件提示 ===\n")
blank_pdf <- file.path(td, "blank.pdf")
grDevices::pdf(blank_pdf, width = 4, height = 4)
graphics::plot.new()
graphics::rect(0.5, 0.5, 3.5, 3.5, col = "gray")
grDevices::dev.off()
e2 <- pdf_extract_pages(blank_pdf)
stopifnot(is_pdf_error(e2), grepl("扫描件", e2, fixed = TRUE))
cat(e2, "\n✅\n")

cat("\n=== 6. is_pdf_error 判定 ===\n")
stopifnot(is_pdf_error("❌ 出错"), !is_pdf_error(list()), !is_pdf_error(NULL))
cat("✅\n")

unlink(td, recursive = TRUE)
cat("\n=== ALL PDF IO TESTS PASSED ✅ ===\n")
