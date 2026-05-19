import Foundation

/// Returns `true` when an error from an async request was a Swift Task
/// cancellation or an URLSession `NSURLErrorCancelled`. Both should be
/// invisible to the user — they happen routinely on pull-to-refresh or
/// when a view re-runs `.task { … }` while a previous request is in
/// flight.
func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
    let msg = nsError.localizedDescription.lowercased()
    return msg.contains("cancelled") || msg.contains("canceled")
}
