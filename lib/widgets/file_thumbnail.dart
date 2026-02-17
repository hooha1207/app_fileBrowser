import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:app_filepicker/core/file_formats.dart';

class FileThumbnail extends StatefulWidget {
  final FileSystemEntity file;
  final double size;
  final double iconSize;
  final BorderRadius? borderRadius;
  final List<String>? imageExtensions;
  final List<String>? videoExtensions;
  final List<String>? audioExtensions;

  const FileThumbnail({
    super.key,
    required this.file,
    this.size = 40,
    this.iconSize = 24,
    this.borderRadius,
    this.imageExtensions,
    this.videoExtensions,
    this.audioExtensions,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  static const _storageChannel = MethodChannel('com.example.app_filepicker/storage');
  static final Map<String, Uint8List> _thumbnailCache = {};
  
  // To avoid redundant loading across all instances
  static final Set<String> _loadingPaths = {};

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _checkAndLoad();
    }
  }

  void _checkAndLoad() {
    if (widget.file is Directory) return;

    final ext = p.extension(widget.file.path).toLowerCase();
    final videoExts = widget.videoExtensions ?? FileFormats.extensions['video']!;
    final audioExts = widget.audioExtensions ?? FileFormats.extensions['audio']!;

    bool isVideo = videoExts.contains(ext);
    bool isAudio = audioExts.contains(ext);

    if ((isVideo || isAudio) && !_thumbnailCache.containsKey(widget.file.path)) {
      if (!_loadingPaths.contains(widget.file.path)) {
        _loadNative(isVideo ? 'video' : 'audio');
      }
    }
  }

  Future<void> _loadNative(String type) async {
    final path = widget.file.path;
    _loadingPaths.add(path);
    try {
      final Uint8List? bytes = await _storageChannel.invokeMethod('getMediaThumbnail', {
        'path': path,
        'type': type,
      });
      if (bytes != null) {
        _thumbnailCache[path] = bytes;
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Error loading thumbnail for $path: $e");
    } finally {
      _loadingPaths.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.file is Directory) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        ),
        child: Center(child: Icon(Icons.folder, size: widget.size * 0.6, color: Colors.amber)),
      );
    }

    final ext = p.extension(widget.file.path).toLowerCase();
    final imageExts = widget.imageExtensions ?? FileFormats.extensions['image']!;
    final videoExts = widget.videoExtensions ?? FileFormats.extensions['video']!;
    final audioExts = widget.audioExtensions ?? FileFormats.extensions['audio']!;
    final docExts = FileFormats.extensions['document']!;

    bool isImage = imageExts.contains(ext);
    bool isVideo = videoExts.contains(ext);
    bool isAudio = audioExts.contains(ext);
    bool isDoc = docExts.contains(ext);

    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;
    if (isImage) { icon = Icons.image; color = Colors.pink; }
    else if (isVideo) { icon = Icons.play_circle_fill; color = Colors.purple; }
    else if (isAudio) { icon = Icons.audiotrack; color = Colors.blue; }
    else if (isDoc) { icon = Icons.description; color = Colors.orange; }
    else if (ext == '.apk') { icon = Icons.android; color = Colors.green; }

    Widget content;
    if (isImage) {
      content = Image.file(
        File(widget.file.path),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (ctx, e, s) => Center(child: Icon(icon, size: widget.iconSize, color: color)),
      );
    } else if (_thumbnailCache.containsKey(widget.file.path)) {
      content = Image.memory(
        _thumbnailCache[widget.file.path]!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) => Center(child: Icon(icon, size: widget.iconSize, color: color)),
      );
    } else {
      content = Center(child: Icon(icon, size: widget.iconSize, color: color));
    }

    return RepaintBoundary(
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}
