import 'dart:io';

/// Custom [HttpOverrides] that permits connections to self-hosted IPTV media servers,
/// local LAN endpoints, and services utilizing self-signed or custom CA certificates.
class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

/// Applies global HTTP certificate validation overrides on native platforms (Mobile & Desktop).
void setupHttpOverrides() {
  try {
    HttpOverrides.global = AppHttpOverrides();
  } catch (_) {}
}
