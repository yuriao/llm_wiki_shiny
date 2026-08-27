# ============================================================
# wiki_graph.R — 知识图谱构建 + visNetwork 可视化
# llm_wiki_shiny (GPL v3.0, 衍生自 nashsu/llm_wiki)
# ============================================================

# 从页面集合构建图数据（nodes / edges）
# 节点：每页一个；边：[[wikilinks]] 指向其他页面（目标不存在也画边，虚线区分）
build_graph_data <- function(pages_df, wiki_root) {
  if (is.null(pages_df) || nrow(pages_df) == 0) {
    return(list(nodes = data.frame(), edges = data.frame()))
  }
  nodes <- data.frame(
    id    = pages_df$relpath,
    label = pages_df$title,
    group = pages_df$type,
    stringsAsFactors = FALSE
  )
  # 标题 → relpath 映射（wikilink 目标是标题）
  title2path <- stats::setNames(pages_df$relpath, pages_df$title)

  edges <- list()
  for (i in seq_len(nrow(pages_df))) {
    page <- read_wiki_page(pages_df$path[i])
    links <- extract_wikilinks(page$body)
    if (length(links) == 0) next
    for (lk in unique(links)) {
      if (lk %in% names(title2path) && title2path[[lk]] != pages_df$relpath[i]) {
        edges[[length(edges) + 1]] <- data.frame(
          from = pages_df$relpath[i], to = title2path[[lk]],
          dashes = FALSE, stringsAsFactors = FALSE
        )
      }
    }
  }
  edges_df <- if (length(edges) > 0) do.call(rbind, edges) else
    data.frame(from = character(0), to = character(0), dashes = logical(0))

  list(nodes = nodes, edges = edges_df)
}

# visNetwork 渲染（按类型着色 + 高亮交互）
render_wiki_graph <- function(graph_data) {
  if (is.null(graph_data) || nrow(graph_data$nodes) == 0) {
    return(visNetwork::visNetwork(
      data.frame(id = character(0), label = character(0)),
      data.frame(from = character(0), to = character(0))
    ))
  }
  n <- graph_data$nodes
  e <- graph_data$edges
  visNetwork::visNetwork(n, e, height = "100%", width = "100%") |>
    visNetwork::visNodes(font = list(size = 16),
                         shadow = list(enabled = TRUE)) |>
    visNetwork::visEdges(arrows = "to", smooth = list(enabled = TRUE),
                         color = list(color = "#94a3b8", highlight = "#f59e0b")) |>
    visNetwork::visGroups(groupname = "entities",   color = list(background = "#3b82f6", border = "#1d4ed8")) |>
    visNetwork::visGroups(groupname = "concepts",   color = list(background = "#10b981", border = "#047857")) |>
    visNetwork::visGroups(groupname = "comparisons", color = list(background = "#f59e0b", border = "#b45309")) |>
    visNetwork::visGroups(groupname = "queries",    color = list(background = "#8b5cf6", border = "#6d28d9")) |>
    visNetwork::visOptions(
      highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE),
      nodesIdSelection = list(enabled = TRUE, main = "跳转到页面"),
      collapse = list(enabled = TRUE)
    ) |>
    visNetwork::visInteraction(navigationButtons = TRUE) |>
    visNetwork::visPhysics(stabilization = list(iterations = 200)) |>
    # 显式绑定节点点击 → Shiny（visNetwork 内置 select 发送机制在 Shiny 2 下不可靠）
    visNetwork::visEvents(
      select = "function(params) {
        if (params.nodes && params.nodes.length > 0) {
          Shiny.setInputValue('graph_node_click', params.nodes[0], {priority: 'event'});
        }
      }"
    )
}
