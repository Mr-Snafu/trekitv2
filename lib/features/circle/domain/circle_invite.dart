class CircleInvite {
  const CircleInvite._(this.trekId);

  static final RegExp _validTrekId = RegExp(r'^TREK-[A-Z0-9]{7,12}$');

  factory CircleInvite.forTrekId(String trekId) {
    final normalized = trekId.trim().toUpperCase();
    if (!_validTrekId.hasMatch(normalized)) {
      throw const FormatException('Invalid TrekIt ID');
    }
    return CircleInvite._(normalized);
  }

  static CircleInvite? fromUri(Uri uri) {
    final normalized = uri.queryParameters['invite']?.trim().toUpperCase();
    if (normalized == null || !_validTrekId.hasMatch(normalized)) return null;
    return CircleInvite._(normalized);
  }

  final String trekId;

  Uri get uri => Uri.https('trekit.online', '/', {'invite': trekId});
}
