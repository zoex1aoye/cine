/// 把播放器的 `open` 串行化。较新的一代会让尚未开始的旧任务直接跳过。
class PlaybackOpenGate {
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  int get generation => _generation;

  /// 换源时调用。正在排队、还没开始的旧 `open` 会看到代数不一致并跳过。
  int bump() => ++_generation;

  Future<void> run(int generation, Future<void> Function() action) {
    final run = _tail.then((_) async {
      if (generation != _generation) return;
      await action();
    });
    _tail = run.catchError((Object _) {});
    return run;
  }
}
