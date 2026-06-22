class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'SAFE_RIDE_API_URL',
    defaultValue: 'https://kshitizsharma-ml-model-for-scoring.hf.space',
  );

  static Uri apiUri(String path) {
    final normalizedBase = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }
}
