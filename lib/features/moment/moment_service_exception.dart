/// 生成朋友圈时出的岔子，用 code 让页面翻成人话。
class MomentServiceException implements Exception {
  const MomentServiceException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => 'MomentServiceException($code)';
}
