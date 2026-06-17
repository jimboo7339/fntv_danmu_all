/// MPV 播放器可调参数，与 libmpv 属性对应。
class MpvPlayerSettings {
  /// auto | auto-safe | auto-copy | mediacodec | mediacodec-copy | no
  final String hwdec;
  /// gpu | gpu-next
  final String vo;
  /// audio | display-resample | display-vdrop
  final String videoSync;
  final int bufferMb;
  final int cacheSecs;
  final bool interpolation;

  const MpvPlayerSettings({
    this.hwdec = 'mediacodec-copy',
    this.vo = 'gpu',
    this.videoSync = 'audio',
    this.bufferMb = 192,
    this.cacheSecs = 25,
    this.interpolation = false,
  });

  int get bufferBytes => bufferMb * 1024 * 1024;

  MpvPlayerSettings copyWith({
    String? hwdec,
    String? vo,
    String? videoSync,
    int? bufferMb,
    int? cacheSecs,
    bool? interpolation,
  }) =>
      MpvPlayerSettings(
        hwdec: hwdec ?? this.hwdec,
        vo: vo ?? this.vo,
        videoSync: videoSync ?? this.videoSync,
        bufferMb: bufferMb ?? this.bufferMb,
        cacheSecs: cacheSecs ?? this.cacheSecs,
        interpolation: interpolation ?? this.interpolation,
      );

  static const hwdecOptions = [
    'auto-copy',
    'auto-safe',
    'auto',
    'mediacodec-copy',
    'mediacodec',
    'no',
  ];
  static const voOptions = ['gpu', 'gpu-next'];
  static const videoSyncOptions = ['display-resample', 'audio', 'display-vdrop'];

  static String hwdecLabel(String value) => switch (value) {
        'auto' => '自动 (Auto)',
        'auto-safe' => 'HW+ 安全',
        'auto-copy' => 'HW+ 拷贝（推荐）',
        'mediacodec' => 'MediaCodec 硬解',
        'mediacodec-copy' => 'MC 拷贝（同步佳）',
        'no' => '软解 (SW)',
        _ => value,
      };

  static String voLabel(String value) => switch (value) {
        'gpu' => 'GPU',
        'gpu-next' => 'GPU-Next',
        _ => value,
      };

  static String videoSyncLabel(String value) => switch (value) {
        'audio' => '跟随音频（推荐）',
        'display-resample' => '显示重采样',
        'display-vdrop' => '显示丢帧',
        _ => value,
      };

  static String hwdecDescription(String value) => switch (value) {
        'auto' => '由 MPV 自动选择解码方式',
        'auto-safe' => '兼容性较好的硬件解码',
        'auto-copy' => '硬解后回拷内存，音画同步更稳定，推荐',
        'mediacodec' => 'Android MediaCodec 直出，部分机型更快',
        'mediacodec-copy' => 'MediaCodec + 回拷，硬解且同步较好',
        'no' => '纯软件解码，兼容性最好但耗电更高',
        _ => '',
      };

  static String voDescription(String value) => switch (value) {
        'gpu' => '稳定通用的 OpenGL 渲染',
        'gpu-next' => '新一代渲染后端，部分设备画面更顺滑',
        _ => '',
      };

  static String videoSyncDescription(String value) => switch (value) {
        'audio' => '视频帧对齐音频时钟，音画同步最稳定',
        'display-resample' => '按显示器刷新率重采样，部分设备可能不同步',
        'display-vdrop' => '丢帧对齐显示，低延迟设备可用',
        _ => '',
      };
}
