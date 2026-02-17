import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:app_filepicker/core/trash_manager.dart';
import 'package:app_filepicker/core/file_utils.dart';

class FileOperationLogic {
  /// 항목 이동 로직
  Future<int> moveItems(List<String> sourcePaths, String destinationPath) async {
    final destDir = Directory(destinationPath);
    if (!destDir.existsSync()) return 0;

    final normalizedDest = p.normalize(destinationPath);
    int movedCount = 0;
    
    for (var sourcePath in sourcePaths) {
      final normalizedSource = p.normalize(sourcePath);
      
      if (p.equals(normalizedSource, normalizedDest)) continue;
      if (p.isWithin(normalizedSource, normalizedDest)) continue;

      final name = p.basename(sourcePath);
      String newPath = p.join(normalizedDest, name);
      
      newPath = FileUtils.getUniquePath(newPath);

      try {
        final entity = FileSystemEntity.isDirectorySync(sourcePath) ? Directory(sourcePath) : File(sourcePath);
        await entity.rename(newPath);
        movedCount++;
      } catch (e) {
        debugPrint("Move error for $sourcePath: $e");
      }
    }
    return movedCount;
  }

  /// 휴지통으로 이동 로직
  Future<void> deleteItems(List<String> paths) async {
    await TrashManager().init();
    for (var path in paths) {
      try {
        final entity = FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);
        await TrashManager().moveToTrash(entity);
      } catch (e) {
        debugPrint("Move to trash error: $e");
      }
    }
  }

  /// 영구 삭제 로직
  Future<void> permanentDeleteItems(List<String> paths) async {
    for (var path in paths) {
      try {
        final entity = FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);
        await entity.delete(recursive: true);
      } catch (e) {
        debugPrint("Permanent delete error: $e");
      }
    }
  }

  /// 새 폴더 생성 로직
  Future<bool> createNewFolder(String parentPath, String folderName) async {
    try {
      final newDir = Directory(p.join(parentPath, folderName.trim()));
      if (!await newDir.exists()) {
        await newDir.create();
        return true;
      }
    } catch (e) {
      debugPrint("Folder creation error: $e");
    }
    return false;
  }



  /// 전역 검색 실행 (Isolate 사용)
  Future<Isolate> spawnSearchIsolate({
    required SendPort sendPort,
    required String rootPath,
    required String query,
    List<String>? extensions,
    List<String>? searchPaths,
  }) {
    return Isolate.spawn(
      searchWorker,
      {
        'sendPort': sendPort,
        'rootPath': rootPath,
        'query': query,
        'extensions': extensions,
        'searchPaths': searchPaths,
      },
    );
  }
}

/// Isolate에서 실행될 워커 (Top-level function)
void searchWorker(Map<String, dynamic> args) {
  final SendPort sendPort = args['sendPort'];
  final String rootPath = args['rootPath'];
  final String query = args['query'].toLowerCase();
  final List<String>? extensions = args['extensions']?.cast<String>();

  try {
    final List<String>? searchPaths = args['searchPaths']?.cast<String>();
    
    if (searchPaths != null && searchPaths.isNotEmpty) {
      for (final path in searchPaths) {
        final dir = Directory(path);
        if (dir.existsSync()) {
          _recursiveSearchWorker(dir, query, extensions, sendPort);
        }
      }
    } else {
      final root = Directory(rootPath);
      if (!root.existsSync()) {
        sendPort.send('error: Root directory not found');
        return;
      }
      _recursiveSearchWorker(root, query, extensions, sendPort);
    }
    sendPort.send('done');
  } catch (e) {
    sendPort.send('error: $e');
  }
}

void _recursiveSearchWorker(Directory dir, String query, List<String>? extensions, SendPort sendPort) {
  try {
    final entities = dir.listSync(followLinks: false);
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue; // 숨김 파일/폴더 제외
      
      final lowerName = name.toLowerCase();
      bool matchesQuery = query.isEmpty || lowerName.contains(query);
      bool matchesExt = true;
      if (extensions != null && entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        matchesExt = extensions.contains(ext);
      } else if (extensions != null && entity is Directory) {
        matchesExt = false;
      }

      if (matchesQuery && matchesExt) {
        int? size;
        DateTime? modified;
        try {
          final stat = entity.statSync();
          size = stat.size;
          modified = stat.modified;
        } catch (_) {}

        sendPort.send({
          'path': entity.path,
          'isDir': entity is Directory,
          'size': size,
          'modified': modified?.millisecondsSinceEpoch,
        });
      }
      
      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        if (dirName != '.trash') {
          _recursiveSearchWorker(entity, query, extensions, sendPort);
        }
      }
    }
  } catch (_) {}
}
