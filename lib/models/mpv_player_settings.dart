/// MPV 播放器可调参数，与 libmpv 属性对应。
class MpvPlayerSettings {
  /// auto | auto-safe | mediacodec | no
  final String hwdec;
  /// gpu | gpu-next
  final String vo;
  final int bufferMb;
  final int cacheSecs;
  final bool interpolation;

  const MpvPlayerSettings({
    this.hwdec = 'auto-safe',
    this.vo = 'gpu',
    this.bufferMb = 192,
    this.cacheSecs = 25,
    this.interpolation = false,
  });

  int get bufferBytes => bufferMb * 1024 * 1024;

  static const hwdecOptions = ['auto', 'auto-safe', 'mediacodec', 'no'];
  static const voOptions = ['gpu', 'gpu-next'];

  static String hwdecLabel(String value) => switch (value) {
        'auto' => '自动 (Auto)',
        'auto-safe' => 'HW+（推荐）',
        'mediacodec' => 'HW 硬解',
        'no' => '软解 (SW)',
        _ => value,
      };

  static String voLabel(String value) => switch (value) {
        'gpu' => 'GPU',
        'gpu-next' => 'GPU-Next',
        _ => value,
      };

  static String hwdecDescription(String value) => switch (value) {
        'auto' => '由 MPV 自动选择解码方式',
        'auto-safe' => '兼容性更好的硬件解码，推荐大多数设备',
        'mediacodec' => 'Android MediaCodec 硬解，部分机型更流畅',
        'no' => '纯软件解码，兼容性最好但耗电更高',
        _ => '',
      };

  static String voDescription(String value) => switch (value) {
        'gpu' => '稳定通用的 OpenGL 渲染',
        'gpu-next' => '新一代渲染后端，部分设备画面更顺滑',
        _ => '',
      };
}
