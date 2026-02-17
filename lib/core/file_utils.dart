import 'dart:io';
import 'package:path/path.dart' as p;

class FileUtils {
  /// Returns a unique path for the given [targetPath] by appending a counter suffix
  /// (e.g., "file (1).txt") if a file or directory already exists at that path.
  static String getUniquePath(String targetPath) {
    if (FileSystemEntity.typeSync(targetPath) != FileSystemEntityType.notFound) {
      final String extension = p.extension(targetPath);
      final String directory = p.dirname(targetPath);
      final String basenameWithoutExt = p.basenameWithoutExtension(targetPath);
      
      int counter = 1;
      String newPath = targetPath;
      
      // Safety limit to prevent infinite loops (max 1000 attempts)
      while (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound && counter <= 1000) {
        newPath = p.join(directory, "$basenameWithoutExt ($counter)$extension");
        counter++;
      }
      return newPath;
    }
    return targetPath;
  }

  /// Formats file size in bytes into human readable format.
  /// If [useDecimal] is true, it uses 1000 as base (e.g. for storage display).
  /// Otherwise, it uses 1024 as base.
  static String formatFileSize(int bytes, {bool useDecimal = false}) {
    if (bytes <= 0) return "0 B";
    final double base = useDecimal ? 1000 : 1024;
    final List<String> units = useDecimal 
        ? ['B', 'KB', 'MB', 'GB', 'TB'] 
        : ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    
    int i = 0;
    double size = bytes.toDouble();
    while (size >= base && i < units.length - 1) {
      size /= base;
      i++;
    }

    if (useDecimal && units[i] == 'GB' && size > 1) {
      final rounded = size.roundToDouble();
      if ((size - rounded).abs() < 0.2) {
        size = rounded;
      }
    }

    return "${size.toStringAsFixed(1)} ${units[i]}";
  }
}
