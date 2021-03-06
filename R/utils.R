# Copyright 2016 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

#' The size of British Columbia
#'
#' Total area, Land area only, or Freshwater area only, in the units of your choosing.
#'
#' The sizes are from \href{http://www.statcan.gc.ca/tables-tableaux/sum-som/l01/cst01/phys01-eng.htm}{Statistics Canada}
#'
#' @param what Which part of BC? One of \code{'total'} (default), \code{'land'}, or \code{'freshwater'}.
#' @param units One of \code{'km2'} (square kilometres; default), \code{'m2'} (square metres),
#'          \code{'ha'} (hectares), \code{'acres'}, or \code{'sq_mi'} (square miles)
#'
#' @return The area of B.C. in the desired units (numeric vector).
#' @export
#'
#' @examples
#' ## With no arguments, gives the total area in km^2:
#' bc_area()
#'
#' ## Get the area of the land only, in hectares:
#' bc_area("land", "ha")
bc_area <- function(what = "total", units = "km2") {
  what = match.arg(what, c("total", "land", "freshwater"))
  units = match.arg(units, c("km2", "m2", "ha", "acres", "sq_mi"))

  val_km2 <- switch(what, total = 944735, land = 925186, freshwater = 19549)
  ret <- switch(units, km2 = val_km2, m2 = km2_m2(val_km2), ha = km2_ha(val_km2),
                acres = km2_acres(val_km2), sq_mi = km2_sq_mi(val_km2))

  ret <- round(ret, digits = 0)
  structure(ret, names = paste(what, units, sep = "_"))
}

km2_m2 <- function(x) {
  x * 1e6
}

km2_ha <- function(x) {
  x * 100
}

km2_acres <- function(x) {
  x * 247.105
}

km2_sq_mi <- function(x) {
  x * 0.386102
}

#' Transform a Spatial* object to BC Albers projection
#'
#' @param sp_obj The Spatial* object to transform
#'
#' @return the Spatial* object in BC Albers projection
#' @export
transform_bc_albers <- function(sp_obj) {
  if (!inherits(sp_obj, "Spatial")) {
    stop("sp_obj must be a Spatial object", call. = FALSE)
  }

  if (!requireNamespace("rgdal", quietly = TRUE)) {
    stop("Package rgdal could not be loaded", call. = FALSE)
  }

  sp::spTransform(sp_obj, sp::CRS("+init=epsg:3005"))
}

#' Check and fix polygons that self-intersect
#'
#' This uses the common method of buffering by zero, using gBuffer in the rgeos package.
#'
#' @param sp_obj The SpatialPolygons* object to check/fix
#'
#' @return The SpatialPolygons* object, repaired if necessary
#' @export
fix_self_intersect <- function(sp_obj) {
  if (!inherits(sp_obj, "SpatialPolygons")) {
    stop("sp_obj must be a Spatial object", call. = FALSE)
  }

  if (!requireNamespace("rgeos", quietly = TRUE)) {
    stop("Package rgdal could not be loaded", call. = FALSE)
  }

  ## Check if the overall geomtry is valid, if it is, exit and return input
  is_valid <- suppressWarnings(rgeos::gIsValid(sp_obj))

  if (is_valid) {
    message("Geometry is valid")
    return(sp_obj)
  }

  ## Check geometry for each polygon
  validity <- rgeos::gIsValid(sp_obj, byid = TRUE, reason = TRUE)
  non_valid <- validity[validity != "Valid Geometry"]

  ## Check if any non-valid objects are due to self intersections. If they are,
  ## repair them, otherwise warn about the other problems
  if (any(grepl("self[ -]intersection", non_valid, ignore.case = TRUE))) {
    ret <- rgeos::gBuffer(sp_obj, byid = TRUE, width = 0)
    message("Self-intersection(s) found - repairing...")
    fix_self_intersect(ret) # check again (yay recursion)
  } else {
    message("No self-intersections found, but there were other problems")
    message(non_valid)
    return(sp_obj)
  }

  ret
}

#' Union a SpatialPolygons* object with itself to remove overlaps, while retaining attributes
#'
#' The IDs of source polygons are stored in a list-column called
#' \code{union_ids}, and original attributes (if present) are stored as nested
#' dataframes in a list-column called \code{union_df}
#'
#' @param x A \code{SpatialPolygons} or \code{SpatialPolygonsDataFrame} object
#'
#' @return A \code{SpatialPolygons} or \code{SpatialPolygonsDataFrame} object
#' @export
#'
#' @examples
#' p1 <- Polygon(cbind(c(2,4,4,1,2),c(2,3,5,4,2)))
#' p2 <- Polygon(cbind(c(5,4,3,2,5),c(2,3,3,2,2)))
#'
#' ps1 <- Polygons(list(p1), "s1")
#' ps2 <- Polygons(list(p2), "s2")
#'
#' spp <- SpatialPolygons(list(ps1,ps2), 1:2)
#'
#' df <- data.frame(a = c("A", "B"), b = c("foo", "bar"),
#'                  stringsAsFactors = FALSE)
#'
#' spdf <- SpatialPolygonsDataFrame(spp, df, match.ID = FALSE)
#'
#' plot(spdf, col = c(rgb(1, 0, 0,0.5), rgb(0, 0, 1,0.5)))
#'
#' unioned_spdf <- self_union(spdf)
#' unioned_sp <- self_union(spp)
self_union <- function(x) {
  if (!inherits(x, "SpatialPolygons")) {
    stop("x must be a SpatialPolygons or SpatialPolygonsDataFrame")
  }

  if (!requireNamespace("raster", quietly = TRUE)) {
    stop("Package raster could not be loaded", call. = FALSE)
  }

  unioned <- raster::union(x)
  unioned$union_ids <- get_unioned_ids(unioned)

  export_cols <- c("union_count", "union_ids")

  if (inherits(x, "SpatialPolygonsDataFrame")) {
    unioned$union_df <- lapply(unioned$union_ids, function(y) x@data[y, ])
    export_cols <- c(export_cols, "union_df")
  }

  names(unioned)[names(unioned) == "count"] <- "union_count"
  unioned[, export_cols]
}

## For each new polygon in a SpatialPolygonsDataFrame that has been unioned with
## itself (raster::union(SPDF, missing)), get the original polygon ids that
## compose it
get_unioned_ids <- function(unioned_sp) {
  id_cols <- grep("^ID\\.", names(unioned_sp@data))
  unioned_sp_data <- as.matrix(unioned_sp@data[, id_cols])
  colnames(unioned_sp_data) <- gsub("ID\\.", "", colnames(unioned_sp_data))

  unioned_ids <- apply(unioned_sp_data, 1, function(i) {
    as.numeric(colnames(unioned_sp_data)[i > 0])
  })

  names(unioned_ids) <- rownames(unioned_sp_data)
  unioned_ids
}

#' Get or calculate the attribute of a list-column containing nested dataframes.
#'
#' For example, \code{self_union} produces a \code{SpatialPolygonsDataFrame}
#' that has a column called \code{union_df}, which contains a \code{data.frame}
#' for each polygon with the attributes from the constituent polygons.
#'
#' @param x the list-column in the (SpatialPolygons)DataFrame that contains nested data.frames
#' @param col the column in the nested data frames from which to retrieve/calculate attributes
#' @param fun function to determine the resulting single attribute from overlapping polygons
#' @param ... other paramaters passed on to \code{fun}
#'
#' @return An atomic vector of the same length as x
#' @export
#'
#' @examples
#' p1 <- Polygon(cbind(c(2,4,4,1,2),c(2,3,5,4,2)))
#' p2 <- Polygon(cbind(c(5,4,3,2,5),c(2,3,3,2,2)))
#' ps1 <- Polygons(list(p1), "s1")
#' ps2 <- Polygons(list(p2), "s2")
#' spp <- SpatialPolygons(list(ps1,ps2), 1:2)
#' df <- data.frame(a = c(1, 2), b = c("foo", "bar"),
#'                  c = factor(c("high", "low"), ordered = TRUE,
#'                             levels = c("low", "high")),
#'                  stringsAsFactors = FALSE)
#' spdf <- SpatialPolygonsDataFrame(spp, df, match.ID = FALSE)
#' plot(spdf, col = c(rgb(1, 0, 0,0.5), rgb(0, 0, 1,0.5)))
#' unioned_spdf <- self_union(spdf)
#' get_poly_attribute(unioned_spdf$union_df, "a", sum)
#' get_poly_attribute(unioned_spdf$union_df, "c", max)
get_poly_attribute <- function(x, col, fun, ...) {
  if (!is(x, "list")) stop("x must be a list, or list-column in a data frame")
  if (!all(vapply(x, is.data.frame, logical(1)))) stop("x must be a list of data frames")
  if (!col %in% names(x[[1]])) stop(col, " is not a column in the data frames in x")
  if (!is.function(fun)) stop("fun must be a function")

  test_data <- x[[1]][[col]]

  return_type <- get_return_type(test_data)

  is_fac <- FALSE

  if (return_type == "factor") {
    is_fac <- TRUE
    lvls <- levels(test_data)
    ordered <- is.ordered(test_data)
    return_type <- "integer"
  }

  return_call <- call(return_type, 1)

  ret <- vapply(x, function(y) {
    fun(y[[col]], ...)
  }, FUN.VALUE = eval(return_call))

  if (is_fac) {
    ret <- factor(lvls[ret], ordered = ordered, levels = lvls)
  }

  ret
}

get_return_type <- function(x) {
  if (is.factor(x)) {
    return_type <- "factor"
  } else {
    return_type <- typeof(x)
  }
}
