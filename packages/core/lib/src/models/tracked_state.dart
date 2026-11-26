/// How far the server is with handling a download.
enum TrackedState {
  downloading,
  importPending,
  importBlocked,
  importing,
  imported,
  failedPending,
  failed,
  ignored,
  unknown,
}
