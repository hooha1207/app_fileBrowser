import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:app_filepicker/screens/browser_screen.dart';
import 'package:app_filepicker/screens/settings_screen.dart';
import 'package:app_filepicker/screens/trash_screen.dart';
import 'package:app_filepicker/core/trash_manager.dart';
import 'package:app_filepicker/core/file_formats.dart';
import 'package:app_filepicker/widgets/file_thumbnail.dart';
import 'package:app_filepicker/core/file_picker_config.dart';
import 'package:app_filepicker/providers/font_provider.dart';
import 'package:app_filepicker/config/app_config.dart';
import 'package:app_filepicker/core/localization.dart';
import 'package:provider/provider.dart';
import 'package:app_filepicker/core/file_utils.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart';
import 'dart:isolate';
import 'dart:async';

// Page transition helper
Route _createRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOut;
      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      var offsetAnimation = animation.drive(tween);
      return SlideTransition(position: offsetAnimation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 230),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  List<FileSystemEntity> _recentFiles = [];
  
  // Storage Info
  String _usedStorage = "0 GB";
  String _totalStorage = "0 GB";
  double _storageProgress = 0.0;

  static const _storageChannel = MethodChannel('com.example.app_filepicker/storage');

  // Real-time monitoring
  final List<StreamSubscription> _subscriptions = [];
  Timer? _debounceTimer;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPermissions();
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  void _onFileChanged(FileSystemEvent event) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _refreshAll();
    });
  }

  void _refreshAll() {
    _fetchStorageInfo();
    _loadRecentFiles();
  }


  Future<void> _initWatchers() async {
    final List<String> watchPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Documents',
    ];

    for (var path in watchPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          final sub = dir.watch().listen(_onFileChanged);
          _subscriptions.add(sub);
        }
      } catch (e) {
        debugPrint("Error watching $path: $e");
      }
    }
  }

  Future<void> _initPermissions() async {
    await Permission.storage.request();
    if (Platform.isAndroid) {
      await Permission.manageExternalStorage.request();
    }
    await TrashManager().init(); // Run cleanup
    if (mounted) {
      setState(() => _isLoading = false);
      _refreshAll();
      _initWatchers();
    }
  }

  Future<void> _fetchStorageInfo() async {
    try {
      final Map<dynamic, dynamic>? result = await _storageChannel.invokeMethod('getStorageInfo');
      if (result != null) {
        final int total = result['total'] ?? 0;
        final int available = result['available'] ?? 0;
        final int used = total - available;

        if (mounted) {
          setState(() {
            _totalStorage = FileUtils.formatFileSize(total, useDecimal: true);
            _usedStorage = FileUtils.formatFileSize(used, useDecimal: true);
            _storageProgress = total > 0 ? used / total : 0.0;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching storage: $e");
    }
  }



  Future<void> _loadRecentFiles() async {
    final List<String> searchPaths = [];
    if (Platform.isAndroid) {
      searchPaths.addAll([
        '/storage/emulated/0/Download',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Documents',
        '/storage/emulated/0/Movies',
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Android/media',
      ]);
    } else {
      final doc = await getApplicationDocumentsDirectory();
      searchPaths.add(doc.path);
    }

    final receivePort = ReceivePort();
    await Isolate.spawn(_recentFileWorker, {
      'sendPort': receivePort.sendPort,
      'paths': searchPaths,
    });

    receivePort.listen((message) {
      if (message is List<String>) {
        if (mounted) {
          setState(() {
            _recentFiles = message.map((p) => File(p)).toList();
          });
        }
        receivePort.close();
      }
    });
  }

  static void _recentFileWorker(Map<String, dynamic> args) async {
    final SendPort sendPort = args['sendPort'];
    final List<String> paths = args['paths'];
    final List<File> allFiles = [];

    for (var path in paths) {
      final dir = Directory(path);
      try {
        if (await dir.exists()) {
          // Shallow search (depth 1)
          final List<FileSystemEntity> entities = await dir.list(recursive: false).toList();
          for (var entity in entities) {
             if (p.basename(entity.path).startsWith('.') || entity.path.contains('/.trash/')) continue;
             if (entity is File) {
               allFiles.add(entity);
             } else if (entity is Directory) {
               // One level deeper
               try {
                 final subEntities = await entity.list(recursive: false).toList();
                 for (var sub in subEntities) {
                   if (p.basename(sub.path).startsWith('.') || sub is! File || sub.path.contains('/.trash/')) continue;
                   allFiles.add(sub);
                 }
               } catch (_) {}
             }
          }
        }
      } catch (_) {}
    }

    allFiles.sort((a, b) {
      try {
        return b.statSync().modified.compareTo(a.statSync().modified);
      } catch (_) {
        return 0;
      }
    });

    final result = allFiles.take(10).map((f) => f.path).toList();
    sendPort.send(result);
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = context.watch<FontSizeProvider>().getScaledSize(16);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search, size: fontSize.iLarge),
            onPressed: () async {
               await Navigator.push(context, _createRoute(const BrowserScreen(autoFocusSearch: true)));
               _refreshAll();
            },
          ),
           IconButton(
            icon: Icon(Icons.more_vert, size: fontSize.iLarge),
            onPressed: () async {
               await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
               _refreshAll();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Material(
                     color: Colors.transparent,
                     child: InkWell(
                       onTap: () async {
                         final List<String> searchPaths = Platform.isAndroid ? [
                           '/storage/emulated/0/Download',
                           '/storage/emulated/0/DCIM',
                           '/storage/emulated/0/Pictures',
                           '/storage/emulated/0/Documents',
                           '/storage/emulated/0/Movies',
                           '/storage/emulated/0/Music',
                           '/storage/emulated/0/Android/media',
                         ] : [];
                         await Navigator.push(context, _createRoute(BrowserScreen(
                           isRecentFilesMode: true,
                           recentSearchPaths: searchPaths,
                         ))); 
                         _refreshAll();
                       },
                       child: Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                         child: Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                             RichText(
                               text: TextSpan(
                                 style: TextStyle(fontSize: fontSize.fBody, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                                 children: [
                                   TextSpan(text: "home_recent_files".tr()),
                                   TextSpan(text: " ${_recentFiles.length}${ 'unit_items'.tr()}", style: TextStyle(fontSize: fontSize.fSmall, fontWeight: FontWeight.normal)), 
                                 ],
                               ),
                             ),
                             Icon(Icons.arrow_forward_ios, size: fontSize.iSmall, color: Colors.grey),
                           ],
                         ),
                       ),
                     ),
                   ),
                   Padding(
                     padding: const EdgeInsets.symmetric(horizontal: 16.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         const SizedBox(height: 16),
                   SizedBox(
                     height: 100 + 8 + (fontSize * 1.2) + (fontSize * 1.0) + 12, // Thumbnail(100) + Spacer(8) + Title + Time + Padding
                     child: _recentFiles.isEmpty 
                      ? Center(child: Text("Empty Folder".tr(), style: TextStyle(fontSize: fontSize.fBody, color: Colors.grey)))
                      : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentFiles.length,
                        separatorBuilder: (_, index) => const SizedBox(width: 12),
                        itemBuilder: (context, index) => _buildRecentFileCard(_recentFiles[index], fontSize),
                      ),
                   ),

                   const SizedBox(height: 16),

                   // 2. Categories
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildCategoryButton('category_images'.tr(), Icons.image, Colors.pink, Theme.of(context).colorScheme.surfaceContainerLow, FileType.image, fontSize)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildCategoryButton('category_videos'.tr(), Icons.play_circle_fill, Colors.purple, Theme.of(context).colorScheme.surfaceContainerLow, FileType.video, fontSize)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildCategoryButton('category_audio'.tr(), Icons.audiotrack, Colors.blue, Theme.of(context).colorScheme.surfaceContainerLow, FileType.audio, fontSize)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildCategoryButton('category_documents'.tr(), Icons.description, Colors.orange, Theme.of(context).colorScheme.surfaceContainerLow, FileType.document, fontSize)),
                          ],
                        ),
                      ],
                    ),
                   const SizedBox(height: 16),

                   // 3. Storage & Downloads
                    Text("storage_title".tr(), style: TextStyle(fontSize: fontSize.fHeader, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 12),
                   _buildStorageItem(
                      icon: Icons.smartphone,
                      title: "storage_internal".tr(),
                      used: _usedStorage,
                      total: _totalStorage,
                      progress: _storageProgress,
                      fontSize: fontSize,
                      onTap: () async {
                         await Navigator.push(context, MaterialPageRoute(builder: (_) => const BrowserScreen()));
                         _refreshAll();
                      },
                   ),
                   const SizedBox(height: 12),
                   _buildStorageItem(
                      icon: Icons.download_rounded,
                      title: "storage_downloads".tr(),
                      fontSize: fontSize,
                      onTap: () async {
                         String path = Platform.isAndroid ? '/storage/emulated/0/Download' : (await getApplicationDocumentsDirectory()).path;
                         final dir = Directory(path);
                         if (await dir.exists()) {
                            if (mounted) {
                              await Navigator.push(context, _createRoute(BrowserScreen(initialDirectory: dir)));
                              _refreshAll();
                            }
                         }
                      },
                   ),

                    if (AppConfig.enableTrash) ...[
                      const SizedBox(height: 16),
                      Text("utility_title".tr(), style: TextStyle(fontSize: fontSize.fHeader, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildUtilityItem(Icons.delete_outline, "utility_trash".tr(), fontSize),
                    ],
                   const SizedBox(height: 32),
                   const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
  
  // Re-adding the utility item helper with unified styling
  Widget _buildUtilityItem(IconData icon, String title, double fontSize) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () async {
          if (title == "utility_trash".tr() || title == "휴지통") {
            await Navigator.push(context, _createRoute(const TrashScreen()));
            _refreshAll();
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: fontSize.iLarge),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: fontSize.fBody, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorageItem({
    required IconData icon,
    required String title,
    String? used,
    String? total,
    double? progress,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: fontSize.iLarge),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: fontSize.fBody, fontWeight: FontWeight.w500)),
              ),
              if (used != null && total != null && progress != null)
                Container(
                  width: 160,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[400]?.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      Center(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: fontSize.fTiny, color: Theme.of(context).colorScheme.onSurface),
                            children: [
                              TextSpan(text: used, style: const TextStyle(fontWeight: FontWeight.bold)),
                              TextSpan(text: " / $total"),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButton(String title, IconData icon, Color iconColor, Color bgColor, FileType type, double fontSize) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () async {
          if (type == FileType.image || type == FileType.video || type == FileType.audio || type == FileType.document || type == FileType.apk) {
             final List<String> filters = [];
             if (type == FileType.image) {
               filters.add('image');
             } else if (type == FileType.video) {
               filters.add('video');
             } else if (type == FileType.audio) {
               filters.add('audio');
             } else if (type == FileType.document) {
               filters.add('document');
             } else if (type == FileType.apk) {
               filters.add('apk');
             }

             await Navigator.push(context, _createRoute(BrowserScreen(
               initialTypeFilter: filters, 
               categoryTitle: title,
             )));
             _refreshAll();
             return;
          }
          
          String? folderPath;
          if (Platform.isAndroid) {
            if (type == FileType.download) {
              folderPath = '/storage/emulated/0/Download';
            } else if (type == FileType.document) {
              folderPath = '/storage/emulated/0/Documents';
            }
          } else {
             folderPath = (await getApplicationDocumentsDirectory()).path;
          }
          
            if (folderPath != null) {
              final dir = Directory(folderPath);
              if (await dir.exists()) {
                 if (mounted) {
                   await Navigator.push(context, _createRoute(BrowserScreen(initialDirectory: dir)));
                   _refreshAll();
                 }
              } else {
               if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title folder not found')));
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: fontSize.hLarge,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: fontSize.iMedium),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontSize: fontSize.fSmall, fontWeight: FontWeight.w500))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentFileCard(FileSystemEntity file, double fontSize) {
    final name = p.basename(file.path);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final result = await OpenFilex.open(file.path);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('파일을 열 수 없습니다: ${result.message}')),
            );
          }
        },
        onLongPress: () async {
          await Navigator.push(context, _createRoute(BrowserScreen(
            isRecentFilesMode: true,
            initialSelectedPaths: [file.path],
          )));
          _refreshAll();
        },
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FileThumbnail(
                file: file, 
                size: 100,
                iconSize: 40, 
                borderRadius: BorderRadius.circular(12)
              ),
              const SizedBox(height: 8),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fontSize * 0.85, fontWeight: FontWeight.bold)),
              _buildTimeAgo(file, fontSize),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeAgo(FileSystemEntity file, double fontSize) {
    String timeAgo = "time_just_now".tr();
    try {
      final modified = file.statSync().modified;
      final diff = DateTime.now().difference(modified);
      if (diff.inDays > 0) {
        timeAgo = "time_days_ago".tr(args: [diff.inDays.toString()]);
      } else if (diff.inHours > 0) {
        timeAgo = "time_hours_ago".tr(args: [diff.inHours.toString()]);
      } else if (diff.inMinutes > 0) {
        timeAgo = "time_minutes_ago".tr(args: [diff.inMinutes.toString()]);
      }
    } catch (_) {}
    return Text(timeAgo, style: TextStyle(fontSize: fontSize * 0.7, color: Colors.grey));
  }
}
