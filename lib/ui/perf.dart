/// A single switch for the low-memory rendering path.
///
/// The app is designed for a shop counter, not a gaming PC. On a large or
/// high-DPI surface the glass shadows, grain, hover tilt and cached pages can
/// multiply into gigabytes of raster memory. Lite mode keeps the layout and the
/// data exactly the same, but drops the layers that cost the most:
///
/// - flat panels instead of shadows and long gradients
/// - one wash and a vignette instead of the full Sora Field
/// - no per-tile hover tilt, rim light or grid wave
/// - no S.S sweep timer
/// - instant theme changes instead of a captured wipe
/// - only the active page is kept alive
///
/// It is turned on automatically for large physical surfaces or by the
/// Appearance setting.
class SoraPerf {
  SoraPerf._();

  static bool lite = const bool.fromEnvironment('SORA_PERF');
}
