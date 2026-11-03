import 'dart:io';

import 'package:path/path.dart' as p;

class LogPathResolver {
  const LogPathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => _workingDir;

  File coreFile() {
    return File(p.join(directory.path, "box.log"));
  }

  File appFile() {
    // Use application documents directory for Android
    try {
      final documentsDir = Directory('/data/data/com.nublime.vpn/files');
      if (documentsDir.existsSync()) {
        return File(p.join(documentsDir.path, "app.log"));
      }
    } catch (e) {
      // Fallback to temporary directory
      final tempDir = Directory.systemTemp;
      return File(p.join(tempDir.path, "nublime_app.log"));
    }
    // Fallback to working directory
    return File(p.join(directory.path, "app.log"));
  }
}
