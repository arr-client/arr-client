/// The methods the services use. Only [get] is a read.
enum HttpMethod {
  /// Read.
  get,

  /// Create or act.
  post,

  /// Replace.
  put,

  /// Change part.
  patch,

  /// Remove.
  delete,
}
