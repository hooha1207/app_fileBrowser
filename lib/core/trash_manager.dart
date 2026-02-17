import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class TrashItem {
  final String id;
  final String originalPath;
  final String trashPath;
  final DateTime deletedAt;
  final String fileName;
  final DateTime lastModified;

  TrashItem({
    required this.id,
    required this.originalPath,
    required this.trashPath,
    required this.deletedAt,
    required this.fileName,
    required this.lastModified,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'trashPath': trashPath,
    'deletedAt': deletedAt.toIso8601String(),
    'fileName': fileName,
    'lastModified': lastModified.toIso8601String(),
  };

  factory TrashItem.fromJson(Map<String, dynamic> json) => TrashItem(
    id: json['id'],
    originalPath: json['originalPath'],
    trashPath: json['trashPath'],
    deletedAt: DateTime.parse(json['deletedAt']),
    fileName: json['fileName'],
    lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : DateTime.now(), // Fallback for legacy items
  );
}

class TrashManager {
  static const String _manifestFile = 'trash_manifest.json';
  static const String _trashDirName = '.trash';

  // Singleton
  static final TrashManager _instance = TrashManager._internal();
  factory TrashManager() => _instance;
  TrashManager._internal();

  List<TrashItem> _items = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _loadManifest();
    _initialized = true;
    _performAutoCleanup();
  }

  Future<Directory> get _trashDir async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDocDir.path, _trashDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> get _manifestIoFile async {
    final trash = await _trashDir;
    return File(p.join(trash.path, _manifestFile));
  }

  Future<void> _loadManifest() async {
    try {
      final file = await _manifestIoFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _items = jsonList.map((e) => TrashItem.fromJson(e)).toList();
      } else {
        _items = [];
      }
    } catch (e) {
      debugPrint("Error loading trash manifest: $e");
      _items = [];
    }
  }

  Future<void> _saveManifest() async {
    try {
      final file = await _manifestIoFile;
      final jsonList = _items.map((e) => e.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint("Error saving trash manifest: $e");
    }
  }

  Future<void> _robustMove(FileSystemEntity entity, String destination) async {
    try {
      // Try rename first (fast, atomic within same filesystem)
      await entity.rename(destination);
    } on FileSystemException catch (e) {
      // If rename fails (common for cross-partition moves), fallback to copy + delete
      debugPrint("Rename failed ($e), falling back to copy-delete for ${entity.path}");
      if (entity is File) {
        await entity.copy(destination);
        await entity.delete();
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destination));
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      final newPath = p.join(destination.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  static const _storageChannel = MethodChannel('com.example.app_filepicker/storage');

  Future<void> _scanFile(String path) async {
    if (Platform.isAndroid) {
      try {
        await _storageChannel.invokeMethod('scanFile', {'path': path});
      } catch (e) {
        debugPrint("Scan error: $e");
      }
    }
  }

  Future<void> moveToTrash(FileSystemEntity entity) async {
    try {
      final trashDir = await _trashDir;
      final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = p.basename(entity.path);
      final DateTime lastModified = entity.statSync().modified;
      final String originalPath = entity.path;
      
      final String trashPath = p.join(trashDir.path, "${uniqueId}_$fileName");

      await _robustMove(entity, trashPath);

      final item = TrashItem(
        id: uniqueId,
        originalPath: originalPath,
        trashPath: trashPath,
        deletedAt: DateTime.now(),
        fileName: fileName,
        lastModified: lastModified,
      );

      _items.add(item);
      await _saveManifest();
      
      await _scanFile(originalPath); // Notify that original is gone
      await _scanFile(trashPath);    // Notify of new trash location (though usually hidden)
    } catch (e) {
      debugPrint("Error moving to trash: $e");
      rethrow;
    }
  }

  Future<void> restore(TrashItem item) async {
    try {
      final bool isDirInTrash = FileSystemEntity.isDirectorySync(item.trashPath);
      final storedEntity = isDirInTrash ? Directory(item.trashPath) : File(item.trashPath);

      if (await storedEntity.exists()) {
        final parentDir = Directory(p.dirname(item.originalPath));
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        await _robustMove(storedEntity, item.originalPath);
        
        // Restore modification date
        try {
          if (!isDirInTrash) {
            final restoredFile = File(item.originalPath);
            await restoredFile.setLastModified(item.lastModified);
          }
        } catch (mte) {
          debugPrint("Note: Could not restore modification date: $mte");
        }

        await _scanFile(item.trashPath);    // Notify trash item gone
        await _scanFile(item.originalPath); // Notify restored item back
      }

      _items.removeWhere((e) => e.id == item.id);
      await _saveManifest();
    } catch (e) {
      debugPrint("Error restoring from trash: $e");
      rethrow;
    }
  }

  Future<void> deletePermanently(TrashItem item) async {
    try {
      final storedEntity = FileSystemEntity.isDirectorySync(item.trashPath) 
          ? Directory(item.trashPath) 
          : File(item.trashPath);
      
      if (await storedEntity.exists()) {
        await storedEntity.delete(recursive: true);
        await _scanFile(item.trashPath); // Notify system it's permanently gone
      }
      
      _items.removeWhere((e) => e.id == item.id);
      await _saveManifest();
    } catch (e) {
      debugPrint("Error deleting permanently: $e");
    }
  }

  Future<void> emptyTrash() async {
    // Copy list to avoid concurrent modification issues during iteration
    final itemsCopy = List<TrashItem>.from(_items);
    for (var item in itemsCopy) {
      await deletePermanently(item);
    }
  }

  List<TrashItem> get items => List.unmodifiable(_items);

  Future<void> _performAutoCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final retentionDays = prefs.getInt('retentionDays') ?? 30; // Default 30 days
    
    // If retention is -1, it means "No Limit" (optional feature, but assuming default exists)
    if (retentionDays < 0) return; 

    final now = DateTime.now();
    final expiredItems = _items.where((item) {
      final diff = now.difference(item.deletedAt).inDays;
      return diff >= retentionDays;
    }).toList();

    for (var item in expiredItems) {
      debugPrint("Auto-cleaning trash item: ${item.fileName} (Deleted ${item.deletedAt})");
      await deletePermanently(item);
    }
  }
}
