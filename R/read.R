
#' read raster/array dataset from file or connection
#'
#' read raster/array dataset from file or connection
#' @param .x character vector with name(s) of file(s) or data source(s) to be read
#' @param options character; opening options
#' @param driver character; driver to use for opening file
#' @param sub integer or logical; sub-datasets to be read
#' @param quiet logical; print progress output?
#' @param NA_value numeric value to be used for conversion into NA values; by default this is read from the input file
#' @param along length-one character or integer, or list; determines how several arrays are combined, see Details.
#' @param RasterIO list with named parameters for GDAL's RasterIO, to further control the extent, resolution and bands to be read from the data source; see details.
#' @param proxy logical; if \code{TRUE}, an object of class \code{stars_proxy} is read which contains array metadata only; if \code{FALSE} the full array data is read in memory.
#' @param curvilinear length two character vector with names of subdatasets holding longitude and latitude values for all raster cells.
#' @param ... passed on to \link{st_as_stars} if \code{curvilinear} was set
#' @return object of class \code{stars}
#' @details In case \code{.x} contains multiple files, they will all be read and combined with \link{c.stars}. Along which dimension, or how should objects be merged? If \code{along} is set to \code{NA} it will merge arrays as new attributes if all objects have identical dimensions, or else try to merge along time if a dimension called \code{time} indicates different time stamps. A single name (or positive value) for \code{along} will merge along that dimension, or create a new one if it does not already exist. If the arrays should be arranged along one of more dimensions with values (e.g. time stamps), a named list can passed to \code{along} to specify them; see example.
#'
#' \code{RasterIO} is a list with zero or more of the following named arguments: 
#' \code{nXOff}, \code{nYOff} (both 1-based: the first row/col has offset value 1), 
#' \code{nXSize}, \code{nYSize}, \code{nBufXSize}, \code{nBufYSize}, \code{bands}, code{resample}.
#' see https://www.gdal.org/classGDALDataset.html#a80d005ed10aefafa8a55dc539c2f69da for their meaning;
#' \code{bands} is an integer vector containing the band numbers to be read (1-based: first band is 1)
#' Note that if \code{nBufXSize} or \code{nBufYSize} are specified for downsampling an image, 
#' resulting in an adjusted geotransform. \code{resample} reflects the resampling method and
#' has to be one of: "nearest_neighbour" (the default),
#' "bilinear", "cubic", "cubic_spline", "lanczos", "average", "mode", or "Gauss".
#' @export
#' @examples
#' tif = system.file("tif/L7_ETMs.tif", package = "stars")
#' (x1 = read_stars(tif))
#' (x2 = read_stars(c(tif, tif)))
#' (x3 = read_stars(c(tif, tif), along = "band"))
#' (x4 = read_stars(c(tif, tif), along = "new_dimensions")) # create 4-dimensional array
#' x1o = read_stars(tif, options = "OVERVIEW_LEVEL=1")
#' t1 = as.Date("2018-07-31")
#' # along is a named list indicating two dimensions:
#' read_stars(c(tif, tif, tif, tif), along = list(foo = c("bar1", "bar2"), time = c(t1, t1+2)))
#' 
#' m = matrix(1:120, nrow = 12, ncol = 10)
#' dim(m) = c(x = 10, y = 12) # named dim
#' st = st_as_stars(m)
#' attr(st, "dimensions")$y$delta = -1
#' attr(st, "dimensions")$y$offset = 12
#' st
#' tmp = tempfile(fileext = ".tif")
#' st_write(st, tmp)
#' (red <- read_stars(tmp))
#' read_stars(tmp, RasterIO = list(nXOff = 1, nYOff = 1, nXsize = 10, nYSize = 12, 
#'    nBufXSize = 2, nBufYSize = 2))[[1]]
#' (red <- read_stars(tmp, RasterIO = list(nXOff = 1, nYOff = 1, nXsize = 10, nYSize = 12,
#'    nBufXSize = 2, nBufYSize = 2)))
#' red[[1]] # cell values of subsample grid:
#' plot(st, reset = FALSE, axes = TRUE, ylim = c(-.1,12.1), xlim = c(-.1,10.1),
#'   main = "nBufXSize & nBufYSize demo", text_values = TRUE)
#' plot(st_as_sfc(red, as_points = TRUE), add = TRUE, col = 'red', pch = 16)
#' plot(st_as_sfc(st_as_stars(st), as_points = FALSE), add = TRUE, border = 'grey')
#' plot(st_as_sfc(red, as_points = FALSE), add = TRUE, border = 'green', lwd = 2)
#' file.remove(tmp)
read_stars = function(.x, ..., options = character(0), driver = character(0), 
		sub = TRUE, quiet = FALSE, NA_value = NA_real_, along = NA_integer_,
		RasterIO = list(), proxy = FALSE, curvilinear = character(0)) {

	x = .x
	if (length(x) > 1) { # loop over data sources:
		ret = lapply(x, read_stars, options = options, driver = driver, sub = sub, quiet = quiet,
			NA_value = NA_value, RasterIO = as.list(RasterIO), proxy = proxy, curvilinear = curvilinear)
		dims = length(dim(ret[[1]][[1]]))
		return(do.call(c, append(ret, list(along = along))))
	}

	data = sf::gdal_read(x, options = options, driver = driver, read_data = !proxy, 
		NA_value = NA_value, RasterIO_parameters = as.list(RasterIO))

	if (length(data$bands) == 0) { # read sub-datasets: different attributes
		sub_names = split_strings(data$sub) # get named list
		sub_datasets = sub_names[seq(1, length(sub_names), by = 2)]
		# sub_datasets = gdal_subdatasets(x, options)[sub] # -> would open x twice

		# FIXME: only tested for NetCDF:
		nms = sapply(strsplit(unlist(sub_datasets), ":"), tail, 1)
		names(sub_datasets) = nms
		sub_datasets = sub_datasets[sub]

		nms = names(sub_datasets)

		.read_stars = function(x, options, driver, quiet, proxy, curvilinear) {
			if (! quiet)
				cat(paste0(tail(strsplit(x, ":")[[1]], 1), ", "))
			read_stars(x, options = options, driver = driver, NA_value = NA_value, 
				RasterIO = as.list(RasterIO), proxy = proxy, curvilinear = curvilinear)
		}
		ret = lapply(sub_datasets, .read_stars, options = options, 
			driver = data$driver[1], quiet = quiet, proxy = proxy, curvilinear = curvilinear)
		if (! quiet)
			cat("\n")
		# return:
		if (length(ret) == 1)
			ret[[1]]
		else
			structure(do.call(c, ret), names = nms)
	} else { # we have one single array:
		if (!isTRUE(sub))
			warning("only one array present: argument 'sub' will be ignored")
		meta_data = structure(data, data = NULL) # take meta_data only
		data = if (proxy)
				.x # names only
			else
				attr(data, "data") # extract data arrays
		if (meta_data$driver[1] == "netCDF")
			meta_data = parse_netcdf_meta(meta_data, x)
		meta_data = parse_gdal_meta(meta_data)
		if (! proxy && !is.null(meta_data$units) && !is.na(meta_data$units)) # set units
			units(data) = try_as_units(meta_data$units)

		newdims = lengths(meta_data$dim_extra)
		if (length(newdims) && !proxy)
			dim(data) = c(dim(data)[1:2], newdims)

		dims = if (proxy) {
				if (length(meta_data$bands) > 1) 
					c(x = meta_data$cols[2], 
					  y = meta_data$rows[2], 
					  band = length(meta_data$bands),
					  lengths(meta_data$dim_extra))
				else
					c(x = meta_data$cols[2], 
					  y = meta_data$rows[2], 
					  lengths(meta_data$dim_extra))
			} else 
				NULL

		# return:
		ret = if (proxy) # no data present, subclass of "stars":
			st_stars_proxy(setNames(list(.x), tail(strsplit(x, .Platform$file.sep)[[1]], 1)),
				create_dimensions_from_gdal_meta(dims, meta_data))
		else
			st_stars(setNames(list(data), tail(strsplit(x, .Platform$file.sep)[[1]], 1)),
				create_dimensions_from_gdal_meta(dim(data), meta_data))
		
		if (length(curvilinear) == 2) {
			lon = paste0(meta_data$driver[1], ":\"", x, "\":", curvilinear[1])
			lat = paste0(meta_data$driver[1], ":\"", x, "\":", curvilinear[2])
			st_as_stars(ret, curvilinear = list(x = read_stars(lon, RasterIO = RasterIO)[[1]], 
				y = read_stars(lat, RasterIO = RasterIO)[[1]]), ...)
		} else
			ret
	}
}
