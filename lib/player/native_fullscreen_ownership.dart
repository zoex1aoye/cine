/// 系统窗口已经处于全屏时，这次全屏不是播放器打开的。
/// 离开播放页或退出内部全屏时不能把它关掉。
bool playerOwnsNativeFullscreen({required bool windowAlreadyFullscreen}) {
  return !windowAlreadyFullscreen;
}
