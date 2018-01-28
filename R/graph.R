#' Build tree graph
#'
#' Build a tree graph from a set of clusterings, metadata and associated
#' aesthetics
#'
#' @param clusterings numeric matrix containing clustering information, each
#' column contains clustering at a separate resolution
#' @param metadata data.frame containing metadata on each sample that can be
#' used as node aesthetics
#' @param prefix string indicating columns containing clustering information
#' @param count_filter count threshold for filtering edges in the clustering
#' graph
#' @param prop_filter proportion threshold for filtering edges in the clustering
#' graph
#' @param node_colour either a value indicating a colour to use for all nodes or
#' the name of a metadata column to colour nodes by
#' @param node_colour_aggr if `node_colour` is a column name than a function to
#' aggregate that column for samples in each cluster
#' @param node_size either a numeric value giving the size of all nodes or the
#' name of a metadata column to use for node sizes
#' @param node_size_aggr if `node_size` is a column name than a function to
#' aggregate that column for samples in each cluster
#' @param node_alpha either a numeric value giving the alpha of all nodes or the
#' name of a metadata column to use for node transparency
#' @param node_alpha_aggr if `node_size` is a column name than a function to
#' aggregate that column for samples in each cluster
#'
#' @return [igraph::igraph] object containing the tree graph
#'
#' @importFrom dplyr %>%
#' @importFrom rlang .data
build_tree_graph <- function(clusterings, prefix, count_filter, prop_filter,
                             metadata, node_colour, node_colour_aggr,
                             node_size, node_size_aggr, node_alpha,
                             node_alpha_aggr) {

    nodes <- get_tree_nodes(clusterings, prefix, metadata, node_colour,
                            node_colour_aggr, node_size, node_size_aggr,
                            node_alpha, node_alpha_aggr)

    edges <- get_tree_edges(clusterings, prefix) %>%
        dplyr::filter(.data$count > count_filter) %>%
        dplyr::filter(.data$proportion > prop_filter)

    graph <- igraph::graph_from_data_frame(edges, vertices = nodes)

    return(graph)
}

#' Get tree nodes
#'
#' Extract the nodes from a set of clusterings and add relevant attributes
#'
#' @param clusterings numeric matrix containing clustering information, each
#' column contains clustering at a separate resolution
#' @param metadata data.frame containing metadata on each sample that can be
#' used as node aesthetics
#' @param prefix string indicating columns containing clustering information
#' @param node_colour either a value indicating a colour to use for all nodes or
#' the name of a metadata column to colour nodes by
#' @param node_colour_aggr if `node_colour` is a column name than a function to
#' aggregate that column for samples in each cluster
#' @param node_size either a numeric value giving the size of all nodes or the
#' name of a metadata column to use for node sizes
#' @param node_size_aggr if `node_size` is a column name than a function to
#' aggregate that column for samples in each cluster
#' @param node_alpha either a numeric value giving the alpha of all nodes or the
#' name of a metadata column to use for node transparency
#' @param node_alpha_aggr if `node_size` is a column name than a function to
#' aggregate that column for samples in each cluster
#'
#' @return data.frame containing node information
get_tree_nodes <- function(clusterings, prefix, metadata, node_colour,
                           node_colour_aggr, node_size, node_size_aggr,
                           node_alpha, node_alpha_aggr) {

    nodes <- lapply(colnames(clusterings), function(res) {
        clustering <- clusterings[, res]
        clusters <- sort(unique(clustering))

        node <- lapply(clusters, function(cluster) {
            is_cluster <- clustering == cluster
            size <- sum(is_cluster)

            res_clean <- as.numeric(gsub(prefix, "", res))
            node_name <- paste0(prefix, res_clean, "C", cluster)

            node_data <- list(node_name, res_clean, cluster, size)
            names(node_data) <- c("node", prefix, "cluster", "size")

            if (node_colour %in% colnames(metadata)) {
                clust_meta <- metadata[is_cluster, node_colour]
                node_data[node_colour] <- node_colour_aggr(clust_meta)
            }

            if (node_size %in% colnames(metadata)) {
                clust_meta <- metadata[is_cluster, node_size]
                node_data[node_size] <- node_size_aggr(clust_meta)
            }

            if (node_alpha %in% colnames(metadata)) {
                clust_meta <- metadata[is_cluster, node_alpha]
                node_data[node_alpha] <- node_alpha_aggr(clust_meta)
            }

            node_data <- data.frame(node_data, stringsAsFactors = FALSE)

            return(node_data)
        })

        node <- do.call("rbind", node)

    })

    nodes <- do.call("rbind", nodes)
    nodes[, prefix] <- factor(nodes[, prefix])

    return(nodes)
}

#' Get tree edges
#'
#' Extract the edges from a set of clusterings
#'
#' @param clusterings numeric matrix containing clustering information, each
#' column contains clustering at a separate resolution
#' @param prefix string indicating columns containing clustering information
#'
#' @return data.frame containing edge information
#'
#' @importFrom dplyr %>%
#' @importFrom rlang .data
get_tree_edges <- function(clusterings, prefix) {

    res_values <- colnames(clusterings)

    edges <- lapply(seq_len(ncol(clusterings) - 1), function(idx) {
        from_res <- res_values[idx]
        to_res <- res_values[idx + 1]

        from_clusters <- sort(unique(clusterings[, from_res]))
        to_clusters <- sort(unique(clusterings[, to_res]))

        from_tos <- expand.grid(from_clust = from_clusters,
                                to_clust = to_clusters,
                                stringsAsFactors = FALSE)

        transitions <- apply(from_tos, 1, function(from_to) {
            from_clust <- from_to[1]
            to_clust <- from_to[2]

            is_from <- clusterings[, from_res] == from_clust
            is_to <- clusterings[, to_res] == to_clust

            trans_count <- sum(is_from & is_to)

            to_size <- sum(is_to)

            trans_prop <- trans_count / to_size

            return(c(trans_count, trans_prop))
        })

        from_tos$from_res <- as.numeric(gsub(prefix, "", from_res))
        from_tos$to_res <- as.numeric(gsub(prefix, "", to_res))
        from_tos$count <- transitions[1, ]
        from_tos$proportion <- transitions[2, ]

        return(from_tos)
    })

    edges <- dplyr::bind_rows(edges) %>%
        dplyr::mutate(from_node = paste0(prefix, .data$from_res,
                                         "C", .data$from_clust)) %>%
        dplyr::mutate(to_node = paste0(prefix, .data$to_res,
                                       "C", .data$to_clust)) %>%
        dplyr::select(.data$from_node, .data$to_node, dplyr::everything())

    return(edges)

}