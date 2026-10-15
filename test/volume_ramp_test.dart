import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rhythmo/features/player/data/volume_ramp.dart';

void main() {
  test('fades smoothly to the target over the given time', () {
    fakeAsync((async) {
      final applied = <double>[];
      final ramp = VolumeRamp(applied.add);
      var done = false;
      ramp.to(0, transportFade).then((_) => done = true);

      async.elapse(const Duration(milliseconds: 75));
      expect(done, isFalse);
      // Raised cosine: halfway in time is halfway in gain.
      expect(ramp.value, closeTo(0.5, 0.1));
      async.elapse(const Duration(milliseconds: 90));
      expect(done, isTrue);
      expect(ramp.value, 0);
      expect(applied.last, 0);
      // Never jumps more than a small step at a time, and never overshoots.
      for (var i = 1; i < applied.length; i++) {
        expect((applied[i] - applied[i - 1]).abs(), lessThan(0.2));
        expect(applied[i], inInclusiveRange(0, 1));
      }
      expect(applied.length, greaterThanOrEqualTo(8));
    });
  });

  test('a new ramp starts where the last one got to', () {
    fakeAsync((async) {
      final applied = <double>[];
      final ramp = VolumeRamp(applied.add);
      var firstDone = false;
      ramp.to(0, transportFade).then((_) => firstDone = true);
      async.elapse(const Duration(milliseconds: 60));
      final reached = ramp.value;
      expect(reached, inExclusiveRange(0, 1));

      ramp.to(1, transportFade);
      async.flushMicrotasks();
      expect(firstDone, isTrue, reason: 'the replaced ramp completes');
      async.elapse(const Duration(milliseconds: 15));
      expect(ramp.value, greaterThan(reached));
      expect(ramp.value - reached, lessThan(0.2));
      async.elapse(transportFade);
      expect(ramp.value, 1);
    });
  });

  test('zero time or no change applies at once', () async {
    final applied = <double>[];
    final ramp = VolumeRamp(applied.add);
    await ramp.to(1, transportFade);
    await ramp.to(0.3, Duration.zero);
    expect(ramp.value, 0.3);
    ramp.jump(2);
    expect(ramp.value, 1);
    expect(applied, [1, 0.3, 1]);
  });
}
