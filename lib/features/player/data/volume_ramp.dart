import 'dart:async';
import 'dart:math';

/// How long pause and resume fade, so the waveform is never cut mid-cycle,
/// which clicks.
const transportFade = Duration(milliseconds: 150);

/// The dip around a seek: out quickly, back in a little slower.
const seekFadeOut = Duration(milliseconds: 30);
const seekFadeIn = Duration(milliseconds: 80);

/// Moves a gain smoothly to a target over a short time, calling [apply] at
/// every step. A new ramp takes over from wherever the last one got to, so
/// quick pause/play taps never jump.
class VolumeRamp {
  VolumeRamp(this.apply, {this.step = const Duration(milliseconds: 15)});

  final void Function(double gain) apply;
  final Duration step;

  double _value = 1;
  Timer? _timer;
  Completer<void>? _done;

  double get value => _value;

  /// Ramps to [target] over [duration] along a raised-cosine curve; the
  /// future completes when it gets there or a newer ramp replaces it.
  Future<void> to(double target, Duration duration) {
    _finish();
    target = target.clamp(0.0, 1.0);
    if (duration <= Duration.zero || _value == target) {
      _set(target);
      return Future.value();
    }
    final done = _done = Completer<void>();
    final start = _value;
    final steps =
        max(1, (duration.inMicroseconds / step.inMicroseconds).ceil());
    var taken = 0;
    _timer = Timer.periodic(step, (timer) {
      taken++;
      final progress = taken / steps;
      final eased = 0.5 - 0.5 * cos(pi * progress);
      _set(start + (target - start) * eased);
      if (taken >= steps) {
        _set(target);
        _finish();
      }
    });
    return done.future;
  }

  /// Sets the gain at once, ending any ramp.
  void jump(double target) {
    _finish();
    _set(target.clamp(0.0, 1.0));
  }

  void _set(double value) {
    _value = value;
    apply(value);
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  void dispose() => _finish();
}
