import 'app_install_service_stub.dart'
    if (dart.library.js_interop) 'app_install_service_web.dart'
    as platform;

enum AppInstallAvailability { unsupported, instructions, available, installed }

class AppInstallService {
  Future<AppInstallAvailability> getAvailability() async {
    if (!platform.isWeb) return AppInstallAvailability.unsupported;
    if (platform.isStandalone) return AppInstallAvailability.installed;
    if (platform.canInstall) return AppInstallAvailability.available;
    return AppInstallAvailability.instructions;
  }

  Future<bool> install() => platform.promptInstall();
}
