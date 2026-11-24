import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// The deployment proxy serves /api on the same origin as the website.
/// Native releases use its absolute URL because they have no browser origin.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kReleaseMode
      ? (kIsWeb ? '/api' : 'https://paragospels.com/api')
      : 'http://127.0.0.1:8010',
);
