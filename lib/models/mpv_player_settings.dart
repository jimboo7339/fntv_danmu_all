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

  /// 硬件解码器详细说明（设置页引导弹窗用）
  static HwdecOptionDetail hwdecDetail(String value) =>
      hwdecDetails.firstWhere((d) => d.value == value, orElse: () => hwdecDetails.first);

  static const hwdecDetails = [
    HwdecOptionDetail(
      value: 'mediacodec-copy',
      badge: HwdecBadge.recommended,
      shortDesc: 'Android 硬解 + 回拷内存，App 默认策略',
      pros: ['音画同步稳定', '内嵌字幕（PGS/ASS）显示正常', '云直链续播、倍速表现好'],
      cons: ['比直出硬解略多一步内存拷贝'],
      scenario: '飞牛 NAS、夸克云直链、需要内嵌字幕时首选',
    ),
    HwdecOptionDetail(
      value: 'auto-copy',
      badge: HwdecBadge.recommended,
      shortDesc: 'MPV 自动挑选硬解方式，并回拷到内存',
      pros: ['通用性好，多数片源可用', '带回拷，同步较稳', '不确定选什么时的稳妥方案'],
      cons: ['具体使用的硬解实现因机型而异'],
      scenario: '日常通用；不确定设备兼容性时选这个',
    ),
    HwdecOptionDetail(
      value: 'auto-safe',
      badge: HwdecBadge.neutral,
      shortDesc: '自动选择兼容性更好的硬解组合',
      pros: ['部分机型硬解崩溃时可缓解', '对老设备相对友好'],
      cons: ['不一定带回拷', '音画/字幕稳定性一般'],
      scenario: '硬解花屏或崩溃时尝试',
    ),
    HwdecOptionDetail(
      value: 'auto',
      badge: HwdecBadge.caution,
      shortDesc: '完全交给 MPV 自动决定',
      pros: ['省心，不用手动挑'],
      cons: ['可能选到直出硬解', '云直链续播、倍速时易音画漂移'],
      scenario: '仅作尝试；同步异常时请改「MC 拷贝」',
    ),
    HwdecOptionDetail(
      value: 'mediacodec',
      badge: HwdecBadge.caution,
      shortDesc: 'MediaCodec 硬解直出屏幕，不经内存回拷',
      pros: ['延迟低', '部分机型 4K 更流畅'],
      cons: ['音画易不同步', 'PGS 位图字幕可能异常', '倍速时问题更明显'],
      scenario: '只追求流畅、不看内嵌字幕、局域网高码率片源',
    ),
    HwdecOptionDetail(
      value: 'no',
      badge: HwdecBadge.fallback,
      shortDesc: 'CPU 软件解码，兼容性最好',
      pros: ['几乎能解所有格式', '滤镜与字幕处理最可控'],
      cons: ['耗电高、发热大', '4K / 高码率可能卡顿'],
      scenario: '硬解全部失败、花屏、崩溃时的最后手段',
    ),
  ];

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

enum HwdecBadge { recommended, neutral, caution, fallback }

class HwdecOptionDetail {
  final String value;
  final HwdecBadge badge;
  final String shortDesc;
  final List<String> pros;
  final List<String> cons;
  final String scenario;

  const HwdecOptionDetail({
    required this.value,
    required this.badge,
    required this.shortDesc,
    required this.pros,
    required this.cons,
    required this.scenario,
  });

  String get label => MpvPlayerSettings.hwdecLabel(value);

  String get badgeText => switch (badge) {
        HwdecBadge.recommended => '推荐',
        HwdecBadge.neutral => '备选',
        HwdecBadge.caution => '慎用',
        HwdecBadge.fallback => '兜底',
      };
}
