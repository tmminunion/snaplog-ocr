class StabilityUpdate {
  final String value;
  final int streak;
  final int requiredFrames;
  final bool shouldCommit;
  final bool inCooldown;

  const StabilityUpdate({
    required this.value,
    required this.streak,
    required this.requiredFrames,
    required this.shouldCommit,
    this.inCooldown = false,
  });
}

/// Tracks consecutive identical OCR readings and commits automatically
/// once [requiredFrames] identical readings are observed, with anti-duplicate cooldown.
class StabilityTracker {
  final int requiredFrames;
  final Duration cooldown;

  String? _candidate;
  int _streak = 0;
  String? _lastCommittedValue;
  DateTime? _lastCommittedAt;

  StabilityTracker({
    this.requiredFrames = 3,
    this.cooldown = const Duration(milliseconds: 2000),
  });

  void resetCandidate() {
    _candidate = null;
    _streak = 0;
  }

  void resetAll() {
    _candidate = null;
    _streak = 0;
    _lastCommittedValue = null;
    _lastCommittedAt = null;
  }

  StabilityUpdate feed(String rawValue, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    final value = rawValue.trim();

    if (value.isEmpty) {
      resetCandidate();
      return StabilityUpdate(
        value: '',
        streak: 0,
        requiredFrames: requiredFrames,
        shouldCommit: false,
      );
    }

    if (_lastCommittedValue == value &&
        _lastCommittedAt != null &&
        ts.difference(_lastCommittedAt!) < cooldown) {
      return StabilityUpdate(
        value: value,
        streak: requiredFrames,
        requiredFrames: requiredFrames,
        shouldCommit: false,
        inCooldown: true,
      );
    }

    if (_candidate == value) {
      _streak += 1;
    } else {
      _candidate = value;
      _streak = 1;
    }

    if (_streak >= requiredFrames) {
      _lastCommittedValue = value;
      _lastCommittedAt = ts;
      resetCandidate();
      return StabilityUpdate(
        value: value,
        streak: requiredFrames,
        requiredFrames: requiredFrames,
        shouldCommit: true,
      );
    }

    return StabilityUpdate(
      value: value,
      streak: _streak,
      requiredFrames: requiredFrames,
      shouldCommit: false,
    );
  }
}

/// Prevents the same QR/Barcode from being auto-captured multiple times
/// within [cooldown].
class BarcodeCooldownTracker {
  final Duration cooldown;

  String? _lastValue;
  DateTime? _lastAt;

  BarcodeCooldownTracker({
    this.cooldown = const Duration(milliseconds: 1800),
  });

  bool shouldAccept(String rawValue, {DateTime? now}) {
    final ts = now ?? DateTime.now();
    final value = rawValue.trim();
    if (value.isEmpty) return false;

    if (_lastValue == value &&
        _lastAt != null &&
        ts.difference(_lastAt!) < cooldown) {
      return false;
    }

    _lastValue = value;
    _lastAt = ts;
    return true;
  }

  void reset() {
    _lastValue = null;
    _lastAt = null;
  }
}
