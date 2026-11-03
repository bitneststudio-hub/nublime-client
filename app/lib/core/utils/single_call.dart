// Single-flight runner: the first caller runs the task, calls that arrive while it
// is in flight are skipped and receive `onIgnored`.
//
// Moved out of connection_notifier.dart so both the connection command gate and the
// B-3 refresh coordinator (R28-F1/F3) share ONE implementation.
class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
