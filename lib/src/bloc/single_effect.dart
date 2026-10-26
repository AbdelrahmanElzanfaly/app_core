/// A one-shot event carried in state: navigation, a toast, a dialog.
///
/// [current] returns the value once and null afterwards, so a rebuild or a
/// second listener cannot replay it.
class SingleEffect<T> {
  SingleEffect(this._value);

  final T _value;
  bool _consumed = false;

  T? get current {
    if (_consumed) return null;
    _consumed = true;
    return _value;
  }

  /// The value, without consuming it.
  T get peek => _value;
}
