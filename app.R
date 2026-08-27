# ============================================================
# llm_wiki_shiny — Karpathy LLM Wiki 模式的 R Shiny 实现
# 衍生自 nashsu/llm_wiki (GPL v3.0)
# 功能：三层浏览 / Markdown 渲染 / [[wikilinks]] / 知识图谱 / 全文搜索 / 编辑 / DeepSeek LLM
# ============================================================

suppressMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(visNetwork)
})

# ---- 加载模块 ----
for (f in c("wiki_io.R", "wiki_render.R", "wiki_graph.R", "wiki_search.R", "llm_client.R")) {
  src_file <- file.path("R", f)
  if (!file.exists(src_file)) stop("缺少模块文件: ", src_file)
  source(src_file, local = TRUE, encoding = "UTF-8")
}

DEFAULT_WIKI <- normalizePath("example_wiki", mustWork = FALSE)

# ---- 目录树 HTML（details/summary 原生折叠） ----
tree_html <- function(tree) {
  items <- names(tree)
  if (length(items) == 0) return("<ul class='wiki-tree'><li><i>（空）</i></li></ul>")
  out <- "<ul class='wiki-tree'>"
  for (nm in items) {
    val <- tree[[nm]]
    if (length(val) == 1 && identical(names(val), "#")) {
      code <- val[[1]]
      out <- paste0(out, sprintf(
        "<li><a href='#' class='tree-leaf' onclick=\"Shiny.setInputValue('tree_click','%s',{priority:'event'});return false;\">%s</a></li>",
        code, htmltools::htmlEscape(nm)))
    } else {
      out <- paste0(out, "<li><details><summary>", htmltools::htmlEscape(nm),
                    "</summary>", tree_html(val), "</details></li>")
    }
  }
  paste0(out, "</ul>")
}

# ---- UI ----
ui <- page_sidebar(
  title = div(style = "display:flex;align-items:center;gap:8px;",
              tags$img(src = "https://raw.githubusercontent.com/nashsu/llm_wiki/main/logo.jpg",
                       height = "28px", style = "border-radius:6px;"),
              "LLM Wiki Shiny"),
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  sidebar = sidebar(
    width = 340,
    card(
      card_header("Wiki 根目录"),
      textInput("wiki_root", NULL, value = DEFAULT_WIKI),
      actionButton("wiki_root_go", "切换目录", class = "btn-primary btn-sm"),
      verbatimTextOutput("wiki_stats", placeholder = TRUE)
    ),
    card(
      card_header("目录结构（三层）"),
      div(class = "tree-scroll", uiOutput("tree_ui")),
      actionButton("new_page", "＋ 新建页面", class = "btn-success btn-sm mt-2")
    )
  ),
  navset_card_underline(
    nav_panel("📖 浏览",
      fluidRow(
        column(10, h4(uiOutput("page_title"))),
        column(2, actionButton("edit_page", "✏️ 编辑", class = "btn-outline-secondary float-end"))
      ),
      uiOutput("page_meta"),
      tags$hr(),
      uiOutput("page_view")
    ),
    nav_panel("🕸️ 知识图谱",
      p("节点 = 页面（按类型着色），边 = [[wikilinks]]。下拉选择或点击节点跳转页面。"),
      visNetworkOutput("graph", height = "70vh")
    ),
    nav_panel("🔍 搜索",
      fluidRow(
        column(9, textInput("search_q", NULL, placeholder = "输入关键词，回车搜索…")),
        column(3, actionButton("search_go", "搜索", class = "btn-primary w-100"))
      ),
      DTOutput("search_results")
    ),
    nav_panel("🤖 LLM（DeepSeek）",
      navset_card_underline(
        nav_panel("问答",
          selectizeInput("qa_pages", "参考页面（可多选，留空则全库检索）",
                         choices = character(0), multiple = TRUE),
          textAreaInput("qa_question", "问题", rows = 3,
                        placeholder = "例如：总结一下知识库里关于 X 的核心观点"),
          actionButton("qa_go", "提问", class = "btn-primary"),
          tags$hr(),
          uiOutput("qa_result")
        ),
        nav_panel("生成页面",
          fluidRow(
            column(6, textInput("gen_title", "标题")),
            column(6, selectInput("gen_type", "类型", choices = WIKI_DIRS))
          ),
          textAreaInput("gen_sources", "参考来源（每行一个，可留空）", rows = 4),
          actionButton("gen_go", "生成草稿", class = "btn-primary"),
          actionButton("gen_save", "保存为页面", class = "btn-success"),
          tags$hr(),
          uiOutput("gen_preview")
        ),
        nav_panel("lint 检查",
          p("检查孤儿页（无入链）、断链（目标不存在）、缺 frontmatter、内容过期（updated >90 天）。"),
          actionButton("lint_go", "运行 lint", class = "btn-warning"),
          tags$hr(),
          verbatimTextOutput("lint_result")
        )
      )
    )
  )
)

# ---- Server ----
server <- function(input, output, session) {
  rv <- reactiveValues(
    wiki_root = DEFAULT_WIKI,
    current_rel = NULL,      # 当前浏览页面 relpath
    current_raw = NULL,      # 当前浏览页面 path（编辑用）
    gen_draft = NULL         # LLM 生成草稿
  )

  pages_df <- reactive({
    req(rv$wiki_root)
    list_wiki_pages(rv$wiki_root)
  })

  known_titles <- reactive(pages_df()$title)

  output$wiki_stats <- renderPrint({
    df <- pages_df()
    sprintf("页面数：%d\n类型分布：%s",
            nrow(df),
            paste(names(table(df$type)), table(df$type), sep = "=", collapse = " "))
  })

  # 目录树
  output$tree_ui <- renderUI({
    req(rv$wiki_root)
    tree <- build_tree_data(rv$wiki_root)
    HTML(tree_html(tree))
  })

  observeEvent(input$wiki_root_go, {
    p <- trimws(input$wiki_root)
    if (!dir.exists(p)) {
      showNotification("目录不存在！", type = "error")
      return()
    }
    rv$wiki_root <- normalizePath(p)
    rv$current_rel <- NULL
    showNotification("已切换 wiki 根目录", type = "message")
  })

  # 树节点点击：page::path / doc::path / raw::path
  observeEvent(input$tree_click, {
    code <- input$tree_click
    parts <- strsplit(code, "::", fixed = TRUE)[[1]]
    if (length(parts) < 2) return()
    kind <- parts[1]
    path <- paste(parts[-1], collapse = "::")
    if (kind %in% c("page", "doc", "raw")) {
      rv$current_raw <- path
      rv$current_rel <- rel_path(path, rv$wiki_root)
    }
  })

  # wikilink 点击（按标题跳转）
  observeEvent(input$wikilink_click, {
    df <- pages_df()
    hit <- df[df$title == input$wikilink_click, ]
    if (nrow(hit) > 0) {
      rv$current_rel <- hit$relpath[1]
      rv$current_raw <- hit$path[1]
    }
  })

  # ---- 浏览 tab ----
  current_page <- reactive({
    req(rv$current_raw, file.exists(rv$current_raw))
    read_wiki_page(rv$current_raw)
  })

  output$page_title <- renderUI({
    if (is.null(rv$current_raw)) return(HTML("<span class='text-muted'>从左侧目录选择页面</span>"))
    page <- current_page()
    typ <- page$frontmatter$type %||% ""
    badge <- if (nzchar(as.character(typ)))
      tags$span(class = paste0("badge type-badge type-", typ), typ) else ""
    tagList(htmltools::htmlEscape(page$title), badge)
  })

  output$page_meta <- renderUI({
    if (is.null(rv$current_raw)) return(NULL)
    page <- current_page()
    fm <- page$frontmatter
    meta <- c()
    if (!is.null(fm$created)) meta <- c(meta, paste0("创建: ", fm$created))
    if (!is.null(fm$updated)) meta <- c(meta, paste0("更新: ", fm$updated))
    if (!is.null(fm$tags))    meta <- c(meta, paste0("标签: ", paste(fm$tags, collapse = ", ")))
    if (length(meta) == 0) return(NULL)
    HTML(paste0("<span class='text-muted small'>", paste(htmltools::htmlEscape(meta), collapse = " · "), "</span>"))
  })

  output$page_view <- renderUI({
    req(rv$current_raw, file.exists(rv$current_raw))
    page <- current_page()
    HTML(render_wiki_page(page, known_titles()))
  })

  # 编辑
  observeEvent(input$edit_page, {
    req(rv$current_raw)
    page <- current_page()
    showModal(modalDialog(
      title = paste0("编辑：", page$title),
      size = "xl",
      textAreaInput("edit_content", "页面内容（YAML frontmatter + markdown 正文）",
                    value = page$raw, rows = 28, width = "100%"),
      footer = tagList(
        modalButton("取消"),
        actionButton("save_page", "保存", class = "btn-success")
      )
    ))
  })

  observeEvent(input$save_page, {
    req(rv$current_raw)
    writeLines(input$edit_content, rv$current_raw, useBytes = TRUE)
    removeModal()
    showNotification("已保存：", basename(rv$current_raw), type = "message")
  })

  # 新建
  observeEvent(input$new_page, {
    showModal(modalDialog(
      title = "新建 wiki 页面",
      textInput("np_title", "标题"),
      selectInput("np_type", "类型", choices = WIKI_DIRS),
      textInput("np_tags", "标签（逗号分隔）"),
      textAreaInput("np_body", "正文（可用 [[wikilink]]）", rows = 12),
      footer = tagList(
        modalButton("取消"),
        actionButton("np_save", "创建", class = "btn-success")
      )
    ))
  })

  observeEvent(input$np_save, {
    req(rv$wiki_root)
    title <- trimws(input$np_title)
    if (!nzchar(title)) { showNotification("标题不能为空", type = "error"); return() }
    tags <- if (nzchar(trimws(input$np_tags))) strsplit(input$np_tags, "[,，]")[[1]] |> trimws() else NULL
    fm <- list(
      title = title, type = input$np_type,
      created = format(Sys.Date()), updated = format(Sys.Date()),
      tags = tags
    )
    fname <- paste0(gsub("[[:punct:][:space:]]+", "-", title), ".md")
    path <- file.path(rv$wiki_root, input$np_type, fname)
    if (file.exists(path)) {
      showNotification("同名文件已存在！", type = "error"); return()
    }
    write_wiki_page(path, fm, input$np_body)
    removeModal()
    rv$current_raw <- path
    rv$current_rel <- rel_path(path, rv$wiki_root)
    showNotification("页面已创建", type = "message")
  })

  # ---- 图谱 tab ----
  output$graph <- renderVisNetwork({
    req(pages_df())
    render_wiki_graph(build_graph_data(pages_df(), rv$wiki_root))
  })

  observeEvent(input$graph_node_click, {
    sel <- input$graph_node_click
    if (is.null(sel) || !nzchar(sel)) return()
    df <- pages_df()
    hit <- df[df$relpath == sel, ]
    if (nrow(hit) > 0) {
      rv$current_rel <- hit$relpath[1]
      rv$current_raw <- hit$path[1]
    }
  })

  observeEvent(input$graph_selected, {
    sel <- input$graph_selected
    if (is.null(sel) || !nzchar(sel)) return()
    df <- pages_df()
    hit <- df[df$relpath == sel, ]
    if (nrow(hit) > 0) {
      rv$current_rel <- hit$relpath[1]
      rv$current_raw <- hit$path[1]
    }
  })

  # ---- 搜索 tab ----
  search_res <- eventReactive(input$search_go, {
    search_wiki(pages_df(), input$search_q, rv$wiki_root)
  }, ignoreNULL = FALSE)

  output$search_results <- renderDT({
    res <- search_res()
    if (nrow(res) == 0) return(datatable(data.frame(提示 = "无结果")))
    datatable(
      res[, c("title", "type", "hit_in", "snippet")],
      colnames = c("标题", "类型", "命中", "片段"),
      selection = "single", rownames = FALSE, filter = "top",
      options = list(pageLength = 10, dom = "ftp")
    )
  })

  observeEvent(input$search_results_rows_selected, {
    res <- search_res()
    if (length(input$search_results_rows_selected) == 0) return()
    row <- res[input$search_results_rows_selected, ]
    rv$current_rel <- row$relpath
    rv$current_raw <- row$path
  })

  # ---- LLM tab ----
  observe({
    updateSelectizeInput(session, "qa_pages", choices = known_titles(), server = TRUE)
  })

  observeEvent(input$qa_go, {
    q <- trimws(input$qa_question)
    if (!nzchar(q)) { showNotification("请输入问题", type = "error"); return() }
    df <- pages_df()
    sel_titles <- input$qa_pages
    ctx_pages <- if (length(sel_titles) > 0)
      lapply(sel_titles, function(t) {
        hit <- df[df$title == t, ]
        if (nrow(hit) > 0) read_wiki_page(hit$path[1]) else NULL
      }) |> Filter(Negate(is.null), x = _)
    else lapply(df$path, read_wiki_page)
    output$qa_result <- renderUI({
      div(class = "alert alert-info", "正在调用 DeepSeek…")
    })
    res <- tryCatch(llm_answer(q, ctx_pages), error = function(e) paste("❌", conditionMessage(e)))
    output$qa_result <- renderUI({
      markdown(res)
    })
  })

  observeEvent(input$gen_go, {
    title <- trimws(input$gen_title)
    if (!nzchar(title)) { showNotification("请输入标题", type = "error"); return() }
    sources <- if (nzchar(trimws(input$gen_sources)))
      strsplit(input$gen_sources, "\n")[[1]] |> trimws() |> Filter(nzchar, x = _) else character(0)
    output$gen_preview <- renderUI(div(class = "alert alert-info", "正在生成…"))
    draft <- tryCatch(
      llm_generate_page(title, input$gen_type, sources),
      error = function(e) paste("❌", conditionMessage(e)))
    rv$gen_draft <- draft
    output$gen_preview <- renderUI({
      if (startsWith(draft, "❌")) return(div(class = "alert alert-danger", draft))
      tagList(
        h6("草稿预览："),
        markdown(draft)
      )
    })
  })

  observeEvent(input$gen_save, {
    req(rv$gen_draft, !startsWith(rv$gen_draft, "❌"))
    draft <- rv$gen_draft
    # 拆分 frontmatter 与正文
    parsed <- tryCatch(parse_frontmatter(draft), error = function(e) NULL)
    title <- input$gen_title
    fm <- if (!is.null(parsed) && length(parsed$fm) > 0) parsed$fm else
      list(title = title, type = input$gen_type,
           created = format(Sys.Date()), updated = format(Sys.Date()))
    body <- if (!is.null(parsed)) parsed$body else draft
    fname <- paste0(gsub("[[:punct:][:space:]]+", "-", title), ".md")
    path <- file.path(rv$wiki_root, input$gen_type, fname)
    if (file.exists(path)) {
      showNotification("同名文件已存在！", type = "error"); return()
    }
    write_wiki_page(path, fm, body)
    rv$current_raw <- path
    rv$current_rel <- rel_path(path, rv$wiki_root)
    showNotification("LLM 生成的页面已保存", type = "message")
  })

  lint_res <- eventReactive(input$lint_go, {
    tryCatch(llm_lint_report(pages_df(), rv$wiki_root),
             error = function(e) paste("❌", conditionMessage(e)))
  }, ignoreNULL = FALSE)

  output$lint_result <- renderPrint(cat(lint_res()))
}

shinyApp(ui, server)
