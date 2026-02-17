import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:app_filepicker/core/localization.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:app_filepicker/core/file_formats.dart';
import 'package:app_filepicker/widgets/file_thumbnail.dart';
import 'dart:isolate';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:open_filex/open_filex.dart';
import 'package:app_filepicker/screens/settings_screen.dart';
import 'package:app_filepicker/core/file_picker_config.dart';
import 'package:app_filepicker/providers/font_provider.dart';
import 'package:app_filepicker/config/app_config.dart';
import 'package:app_filepicker/core/file_operation_logic.dart';
import 'package:app_filepicker/widgets/file_item_tile.dart';


// --- Enums & Models ---


import 'package:app_filepicker/core/file_utils.dart';

// Wrapper class for FileSystemEntity with cached metadata
class FileItem {
  final FileSystemEntity entity;
  final int? size;
  final DateTime? modified;

  FileItem({
    required this.entity,
    this.size,
    this.modified,
  });

  String get path => entity.path;
}

class BrowserScreen extends StatefulWidget {
  final Directory? initialDirectory;
  final bool autoFocusSearch;
  final List<String>? initialTypeFilter;
  final String? categoryTitle;
  final List<String>? initialSelectedPaths;
  final bool isRecentFilesMode;
  final List<String>? recentSearchPaths;

  const BrowserScreen({
    super.key, 
    this.initialDirectory, 
    this.autoFocusSearch = false,
    this.initialTypeFilter,
    this.categoryTitle,
    this.initialSelectedPaths,
    this.isRecentFilesMode = false,
    this.recentSearchPaths,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with TickerProviderStateMixin {
  Directory? _rootDirectory;
  Directory? _currentDirectory;
  List<FileItem> _files = [];
  List<FileItem> _filteredFiles = [];
  
  // UI State
  bool _isLoading = false;
  bool _isSelectionMode = false;
  String? _selectionMode; // 'select' ?먮뒗 'delete'
  bool _isMovingMode = false; // ?대룞 ?꾩튂 ?좏깮 紐⑤뱶
  final Set<String> _selectedPaths = {};
  List<String> _pathsToMove = []; // ?대룞?????寃쎈줈??

  // Search & Filter
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<String> _typeFilter = [];
  bool _isSearching = false;

  // Config
  late FilePickerConfig _config;
  final FileOperationLogic _logic = FileOperationLogic();
  String? _categoryTitle;
  
  // Scrolling
  final ScrollController _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  double _scrollSpeed = 0;
  final GlobalKey _scrollableKey = GlobalKey();

  // Isolate for streaming search
  Isolate? _searchIsolate;
  ReceivePort? _searchReceivePort;
  Timer? _searchBatchTimer;
  final List<FileItem> _searchPendingFiles = [];

  @override
  void initState() {
    super.initState();
    _config = FilePickerConfig();
    _isSearching = widget.autoFocusSearch;
    if (widget.initialSelectedPaths != null && widget.initialSelectedPaths!.isNotEmpty) {
      _isSelectionMode = true;
      _selectedPaths.addAll(widget.initialSelectedPaths!);
    }
    
    if (widget.categoryTitle != null) {
      _categoryTitle = widget.categoryTitle;
    }
    if (widget.initialTypeFilter != null) {
      _typeFilter = List.from(widget.initialTypeFilter!);
    }

    if (widget.isRecentFilesMode) {
      _config.sortType = SortType.date;
      _config.sortOrder = SortOrder.descending;
      _isLoading = true; // Set early to prevent flicker
    }

    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _stopSearchIsolate();
    _stopAutoScroll();
    super.dispose();
  }

  void _stopSearchIsolate() {
    _searchIsolate?.kill(priority: Isolate.immediate);
    _searchIsolate = null;
    _searchReceivePort?.close();
    _searchReceivePort = null;
    _searchBatchTimer?.cancel();
    _searchBatchTimer = null;
    _searchPendingFiles.clear();
  }

  Future<void> _init() async {
    Directory defaultRoot = Platform.isAndroid 
      ? Directory('/storage/emulated/0/') 
      : await getApplicationDocumentsDirectory();
  
  _rootDirectory = Directory(p.normalize(defaultRoot.path));

  if (widget.initialDirectory != null) {
    _currentDirectory = Directory(p.normalize(widget.initialDirectory!.path));
  } else {
    _currentDirectory = _rootDirectory;
  }
    
    if ((widget.categoryTitle != null && widget.initialTypeFilter != null) || widget.isRecentFilesMode) {
      _performGlobalSearch("");
    } else {
      _listDirectory();
    }
  }

  Future<void> _listDirectory() async {
    if (_currentDirectory == null) return;
    setState(() => _isLoading = true);
    _files.clear();
    try {
      final List<FileSystemEntity> entities = await _currentDirectory!.list().toList();
      
      // Fetch metadata in parallel for local directory listing
      final List<FileItem> items = await Future.wait(entities.map((e) async {
        if (e is Directory) return FileItem(entity: e);
        try {
          final stat = await e.stat();
          return FileItem(entity: e, size: stat.size, modified: stat.modified);
        } catch (_) {
          return FileItem(entity: e);
        }
      }));

      _files = items;
      _applyFiltersAndSort();
    } catch (e) {
      debugPrint("List error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFiltersAndSort() {
    List<FileItem> temp = List.from(_files);

    if (_typeFilter.isNotEmpty) {
      final exts = _typeFilter.expand((type) => FileFormats.extensions[type] ?? <String>[]).toSet();
      temp = temp.where((item) {
        if (item.entity is Directory) return true;
        final ext = p.extension(item.path).toLowerCase();
        return exts.contains(ext);
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      temp = temp.where((item) {
        return p.basename(item.path).toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (widget.isRecentFilesMode) {
      temp = temp.where((item) => item.entity is File).toList();
    }

    temp.sort((a, b) {
      if (a.entity is Directory && b.entity is File) return -1;
      if (a.entity is File && b.entity is Directory) return 1;

      int compareResult = 0;
      switch (_config.sortType) {
        case SortType.name:
          compareResult = p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
          break;
        case SortType.date:
          final aDate = a.modified ?? DateTime(0);
          final bDate = b.modified ?? DateTime(0);
          compareResult = aDate.compareTo(bDate);
          break;
        case SortType.type:
           compareResult = p.extension(a.path).toLowerCase().compareTo(p.extension(b.path).toLowerCase());
           break;
        case SortType.size:
          if (a.entity is File && b.entity is File) {
             compareResult = (a.size ?? 0).compareTo(b.size ?? 0);
          }
          break;
      }
      return _config.sortOrder == SortOrder.ascending ? compareResult : -compareResult;
    });

    _filteredFiles = temp;
  }

  Future<void> _performGlobalSearch(String query) async {
    if (_rootDirectory == null) return;
    if (!widget.isRecentFilesMode && _categoryTitle == null && query.isEmpty) return;

    _stopSearchIsolate();

    setState(() {
      _isLoading = true;
      _files = [];
      _filteredFiles = [];
    });

    _searchReceivePort = ReceivePort();

    try {
      _searchIsolate = await _logic.spawnSearchIsolate(
        sendPort: _searchReceivePort!.sendPort,
        rootPath: _rootDirectory!.path,
        query: query,
        extensions: _categoryTitle != null ? _typeFilter.expand((t) => FileFormats.extensions[t] ?? <String>[]).toList() : null,
        searchPaths: widget.recentSearchPaths,
      );

      _searchReceivePort!.listen((message) {
        if (message is String) {
          if (message == 'done') {
            _flushSearchBuffer();
            if (mounted) setState(() => _isLoading = false);
          } else if (message.startsWith('error:')) {
            debugPrint("Global search isolate error: ${message.substring(6)}");
            if (mounted) setState(() => _isLoading = false);
          }
        } else if (message is Map<String, dynamic>) {
          final String path = message['path'];
          final bool isDir = message['isDir'];
          final int? size = message['size'];
          final int? modifiedMs = message['modified'];
          
          final entity = isDir ? Directory(path) : File(path);
          final modified = modifiedMs != null ? DateTime.fromMillisecondsSinceEpoch(modifiedMs) : null;
          
          _searchPendingFiles.add(FileItem(entity: entity, size: size, modified: modified));
          
          if (_searchBatchTimer == null) {
            _searchBatchTimer = Timer(const Duration(milliseconds: 200), _flushSearchBuffer);
          }
        }
      });
    } catch (e) {
      debugPrint("Global search spawn error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _flushSearchBuffer() {
    if (_searchPendingFiles.isEmpty) {
      _searchBatchTimer = null;
      return;
    }

    if (mounted) {
      setState(() {
        _files.addAll(_searchPendingFiles);
        _searchPendingFiles.clear();
        _applyFiltersAndSort();
      });
    }
    _searchBatchTimer = null;
  }

  void _navigateTo(Directory dir, {bool ignoreSelectionMode = false}) async {
    if (_isSelectionMode && !ignoreSelectionMode) return;
    
    final normalizedPath = p.normalize(dir.path);
    final targetDir = Directory(normalizedPath);

    setState(() {
      _isLoading = true;
      _currentDirectory = targetDir;
    });
    
    await _listDirectory();
  }

  void _handleScrollOnDrag(Offset globalPosition) {
    final RenderBox? renderBox = _scrollableKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localPosition = renderBox.globalToLocal(globalPosition);
    final double height = renderBox.size.height;
    const double threshold = 60.0;
    const double maxSpeed = 15.0;

    if (localPosition.dy < threshold) {
      // Scroll Up
      _scrollSpeed = -((threshold - localPosition.dy) / threshold) * maxSpeed;
      _startAutoScroll();
    } else if (localPosition.dy > height - threshold) {
      // Scroll Down
      _scrollSpeed = ((localPosition.dy - (height - threshold)) / threshold) * maxSpeed;
      _startAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll() {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController.hasClients) {
        final newOffset = _scrollController.offset + _scrollSpeed;
        if (newOffset < _scrollController.position.minScrollExtent) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
          _stopAutoScroll();
        } else if (newOffset > _scrollController.position.maxScrollExtent) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          _stopAutoScroll();
        } else {
          _scrollController.jumpTo(newOffset);
        }
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _scrollSpeed = 0;
  }

  Future<bool> _onWillPop() async {
    if (_isMovingMode) {
      setState(() {
        _isMovingMode = false;
        _pathsToMove = [];
      });
      return false;
    }

    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        _selectionMode = null;
        _selectedPaths.clear();
      });
      return false;
    }

    if (_isSearching) {
       setState(() {
          _isSearching = false;
          _searchQuery = "";
          _searchController.clear();
          _applyFiltersAndSort();
       });
       return false;
    }

    if (widget.categoryTitle != null) {
       return true; 
    }

    if (_currentDirectory != null && _rootDirectory != null) {
      final currentPath = p.normalize(_currentDirectory!.path);
      final rootPath = p.normalize(_rootDirectory!.path);

      if (p.equals(currentPath, rootPath)) {
        return true;
      } else {
        _navigateTo(_currentDirectory!.parent);
        return false;
      }
    }
    
    return true;
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _isSelectionMode = false;
          _selectionMode = null;
        }
      } else {
        _selectedPaths.add(path);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _isSelectionMode = true;
      for (var item in _filteredFiles) {
        _selectedPaths.add(item.path);
      }
    });
  }


  Future<void> _moveItems(List<String> sourcePaths, String destinationPath) async {
    if (sourcePaths.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final movedCount = await _logic.moveItems(sourcePaths, destinationPath);

      if (movedCount > 0) {
        setState(() {
          _selectedPaths.clear();
          _isSelectionMode = false;
        });
        await _listDirectory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("items_moved_count".tr(args: [movedCount.toString()]))));
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  PreferredSizeWidget _buildAppBar(double fontSize) {
    String title = "";
    if (_isMovingMode) {
      title = "moving_location_title".tr();
    } else if (_isSelectionMode) {
      title = "items_selected".tr(args: [_selectedPaths.length.toString()]);
    } else {
      title = (widget.isRecentFilesMode ? "recent_files_title".tr() : (_categoryTitle ?? (_currentDirectory != null ? p.basename(_currentDirectory!.path) : "navigation_browse".tr())));
    }

    return AppBar(
      title: (_isSearching && !_isSelectionMode && !_isMovingMode)
        ? TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: fontSize.fBody),
            decoration: InputDecoration(
              hintText: 'search_hint'.tr(),
              border: InputBorder.none,
              hintStyle: TextStyle(fontSize: fontSize.fBody, color: Colors.grey[400]),
            ),
            onChanged: (val) {
               setState(() {
                 _searchQuery = val;
                 _applyFiltersAndSort();
               });
            },
            onSubmitted: (val) {
              _performGlobalSearch(val);
            },
          )
        : Text(title, style: TextStyle(fontSize: fontSize.fBody, color: Theme.of(context).colorScheme.onSurface)),
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(_isMovingMode ? Icons.close : Icons.arrow_back),
        onPressed: () async {
           if (_isMovingMode) {
             _cancelMoving();
           } else if (_isSearching && !_isSelectionMode) {
             setState(() {
               _isSearching = false;
               _searchQuery = "";
               _searchController.clear();
               _applyFiltersAndSort();
             });
           } else {
             final shouldPop = await _onWillPop();
             if (shouldPop && context.mounted) Navigator.pop(context);
           }
        },
      ),
      actions: [
        if (!_isSelectionMode) ...[
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'search_hint'.tr(),
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
          if (!widget.isRecentFilesMode)
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'action_create_folder'.tr(),
            onPressed: _createNewFolder,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: fontSize.iLarge),
            onSelected: (value) async {
              switch (value) {
                case 'select':
                  setState(() {
                    _isSelectionMode = true;
                    _selectionMode = 'select';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("select_hint".tr()), duration: const Duration(seconds: 2)));
                  break;
                case 'move':
                  setState(() {
                    _isSelectionMode = true;
                    _selectionMode = 'move';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("move_hint".tr()), duration: const Duration(seconds: 2)));
                  break;
                case 'delete':
                  setState(() {
                    _isSelectionMode = true;
                    _selectionMode = 'delete';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("delete_hint".tr()), duration: const Duration(seconds: 2)));
                  break;

                case 'settings':
                   await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                   setState(() {});
                   break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'select', child: Row(children: [const Icon(Icons.checklist, size: 20), const SizedBox(width: 12), Text("action_select_mode".tr())])),
              PopupMenuItem(value: 'move', child: Row(children: [const Icon(Icons.drive_file_move_outline, size: 20), const SizedBox(width: 12), Text("action_move".tr())])),
              PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline, size: 20), const SizedBox(width: 12), Text("action_delete".tr())])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'settings', child: Row(children: [const Icon(Icons.settings, size: 20), const SizedBox(width: 12), Text("action_settings".tr())])),
            ],
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.check_box),
            tooltip: 'action_selectAll'.tr(),
            onPressed: _selectAll,
          ),
          if (_selectedPaths.isNotEmpty) ...[
          if (_selectionMode != 'delete')
            IconButton(
              icon: const Icon(Icons.drive_file_move),
              tooltip: 'action_move_items'.tr(),
              onPressed: _moveSelected,
            ),
          if (AppConfig.enableTrash && _selectionMode != 'move')
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'action_trash'.tr(),
              onPressed: _deleteSelected,
            ),
        ],
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'delete_perm':
                _permanentDeleteSelected();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'delete_perm', 
              child: Row(
                children: [
                   const Icon(Icons.delete_forever, color: Colors.red, size: 20), 
                   const SizedBox(width: 12), 
                   Text("action_permanent_delete".tr(), style: const TextStyle(color: Colors.red))
                ]
              )
            ),
          ],
        ),
        ]
      ],
    );
  }

  Widget _buildParentTile(ViewMode mode, double fontSize) {
    if (_currentDirectory == null) return const SizedBox.shrink();
    final parent = _currentDirectory!.parent;
    if (parent.path == _currentDirectory!.path) return const SizedBox.shrink();

    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        _moveItems(details.data, parent.path);
      },
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty;
        final double baseFontSize = fontSize;

        if (mode == ViewMode.list) {
          return Material(
            color: Colors.transparent,
            child: Ink(
              color: isDraggingOver ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
              child: InkWell(
                onTap: () => _navigateTo(parent, ignoreSelectionMode: true),
                child: Container(
                  decoration: BoxDecoration(
                    border: isDraggingOver ? Border.all(color: Colors.blue, width: 2) : null,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      FileThumbnail(file: parent, size: fontSize.iHuge * 0.625, iconSize: fontSize.iSmall),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text("navigation_parent_folder".tr(), style: TextStyle(fontSize: baseFontSize), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),

                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  color: isDraggingOver ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
                  border: Border.all(
                    color: isDraggingOver ? Colors.blue : Colors.transparent, 
                    width: isDraggingOver ? 2 : 1
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _navigateTo(parent, ignoreSelectionMode: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        FileThumbnail(
                          file: parent,
                          size: fontSize.iMedium * 1.5,
                          iconSize: fontSize.fHeader,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "navigation_parent_folder".tr(),
                            style: TextStyle(
                              fontSize: baseFontSize * 0.9,
                              fontWeight: FontWeight.normal,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            textAlign: TextAlign.start,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildListTile(int index, double fontSize, bool hasParent) {
    final itemIndex = hasParent ? index - 1 : index;
    final entity = _filteredFiles[itemIndex].entity;
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    final isSelected = _selectedPaths.contains(entity.path);
    final isMovingTarget = _pathsToMove.contains(entity.path);
    
    // Determine neighbor highlighted states for border merging
    bool hasHighlightAbove = false;
    if (index > 0) {
      if (hasParent && index == 1) {
        hasHighlightAbove = false;
      } else {
        final aboveIndex = hasParent ? index - 2 : index - 1;
        if (aboveIndex >= 0) {
          final abovePath = _filteredFiles[aboveIndex].path;
          hasHighlightAbove = _selectedPaths.contains(abovePath) || _pathsToMove.contains(abovePath);
        }
      }
    }

    bool hasHighlightBelow = false;
    if (index < _filteredFiles.length + (hasParent ? 0 : -1)) {
      final belowIndex = hasParent ? index : index + 1;
      if (belowIndex < _filteredFiles.length) {
        final belowPath = _filteredFiles[belowIndex].path;
        hasHighlightBelow = _selectedPaths.contains(belowPath) || _pathsToMove.contains(belowPath);
      }
    }

    String subtitle = "";
    if (!isDir) {
      try {
        final stat = entity.statSync();
        subtitle = "${DateFormat('yy-MM-dd HH:mm').format(stat.modified)}  |  ${FileUtils.formatFileSize(stat.size)}";
      } catch (_) {}
    }

    final Widget tile = ListTile(
      leading: FileThumbnail(file: entity, size: fontSize.iHuge * 0.625, iconSize: fontSize.iSmall),
      title: Text(
        name, 
        style: TextStyle(
          fontSize: fontSize.fBody,
          fontWeight: isMovingTarget ? FontWeight.bold : FontWeight.normal,
          color: isMovingTarget ? Colors.blue[700] : Theme.of(context).colorScheme.onSurface,
        ), 
        maxLines: 1, 
        overflow: TextOverflow.ellipsis
      ),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: TextStyle(fontSize: fontSize.fSmall)) : null,
      trailing: _isSelectionMode 
        ? Checkbox(
            value: isSelected,
            onChanged: (val) => _toggleSelection(entity.path),
          )
        : null,
    );

    final itemTile = FileItemTile(
      entity: entity,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      isMovingTarget: isMovingTarget,
      hasHighlightAbove: hasHighlightAbove,
      hasHighlightBelow: hasHighlightBelow,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(entity.path);
        } else {
          if (entity is Directory) {
            _navigateTo(entity);
          } else {
            OpenFilex.open(entity.path).then((result) {
              if (result.type != ResultType.done && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('error_file_open'.tr(args: [result.message]))),
                );
              }
            });
          }
        }
      },
      onLongPress: () {
        if (!isSelected) {
          setState(() {
            _isSelectionMode = true;
            _selectedPaths.add(entity.path);
          });
        }
      },
      onSelectionChanged: (val) => _toggleSelection(entity.path),
      onDragUpdate: _handleScrollOnDrag,
      onDragEnd: _stopAutoScroll,
      dragData: isSelected ? _selectedPaths.toList() : [..._selectedPaths, entity.path],
      feedback: _buildFeedback(entity, name, isSelected, fontSize, ViewMode.list),
      isDraggingDisabled: (_isMovingMode || _selectionMode == 'move') && !isDir && !isMovingTarget,
      child: Stack(
        children: [
          tile,
          if (isMovingTarget && !hasHighlightAbove)
            Positioned(
              top: 0,
              right: 16,
              child: _buildMoveLabel(fontSize),
            ),
        ],
      ),
    );

    return isDir ? _buildDragTarget(entity, itemTile) : itemTile;
  }

  Widget _buildGridTile(FileSystemEntity entity, {double? height, double? thumbnailSize, double? iconSize, required double fontSize}) {
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    final isSelected = _selectedPaths.contains(entity.path);
    final isMovingTarget = _pathsToMove.contains(entity.path);
    final double safeFontSize = fontSize.fBody * 0.9;

    final Widget gridContent = Row(
      children: [
        FileThumbnail(
          file: entity,
          size: thumbnailSize ?? fontSize.iMedium * 1.5,
          iconSize: iconSize ?? fontSize.fHeader,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: safeFontSize,
              fontWeight: (height != null || isMovingTarget) ? FontWeight.bold : FontWeight.normal,
              color: isMovingTarget ? Colors.blue[700] : Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.start,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_isSelectionMode) ...[
          const SizedBox(width: 4),
          Checkbox(
            value: isSelected,
            onChanged: (val) => _toggleSelection(entity.path),
          ),
        ],
      ],
    );

    final itemTile = FileItemTile(
      entity: entity,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      isMovingTarget: isMovingTarget,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(entity.path);
        } else {
          if (entity is Directory) {
            _navigateTo(entity);
          } else {
            OpenFilex.open(entity.path).then((result) {
              if (result.type != ResultType.done && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('error_file_open'.tr(args: [result.message]))),
                );
              }
            });
          }
        }
      },
      onLongPress: () {
        if (!isSelected) {
          setState(() {
            _isSelectionMode = true;
            _selectedPaths.add(entity.path);
          });
        }
      },
      onSelectionChanged: (val) => _toggleSelection(entity.path),
      onDragUpdate: _handleScrollOnDrag,
      onDragEnd: _stopAutoScroll,
      dragData: isSelected ? _selectedPaths.toList() : [..._selectedPaths, entity.path],
      feedback: _buildFeedback(entity, name, isSelected, fontSize, ViewMode.grid),
      isDraggingDisabled: (_isMovingMode || _selectionMode == 'move') && !isDir && !isMovingTarget,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: gridContent,
          ),
          if (isMovingTarget)
            Positioned(
              top: 0,
              right: 0,
              child: _buildMoveLabel(fontSize, isGrid: true),
            ),
        ],
      ),
    );

    return isDir ? _buildDragTarget(entity, itemTile) : itemTile;
  }

  Widget _buildSquareTile(FileSystemEntity entity, double fontSize) {
    final name = p.basename(entity.path);
    final isSelected = _selectedPaths.contains(entity.path);
    final isMovingTarget = _pathsToMove.contains(entity.path);
    final isDir = entity is Directory;
    final double baseFontSize = fontSize.fBody;

    final Widget squareContent = Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: FileThumbnail(
                  file: entity,
                  size: double.infinity,
                  iconSize: fontSize.iHuge * 0.625,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: baseFontSize * 0.85,
                        fontWeight: isMovingTarget ? FontWeight.bold : FontWeight.w500,
                        color: isMovingTarget ? Colors.blue[700] : Theme.of(context).colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (val) => _toggleSelection(entity.path),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (isMovingTarget)
          Positioned(
            top: 0,
            right: 0,
            child: _buildMoveLabel(fontSize, isSquare: true),
          ),
      ],
    );

    final itemTile = FileItemTile(
      entity: entity,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      isMovingTarget: isMovingTarget,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(entity.path);
        } else {
          if (entity is Directory) {
            _navigateTo(entity);
          } else {
            OpenFilex.open(entity.path).then((result) {
              if (result.type != ResultType.done && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('error_file_open'.tr(args: [result.message]))),
                );
              }
            });
          }
        }
      },
      onLongPress: () {
        if (!isSelected) {
          setState(() {
            _isSelectionMode = true;
            _selectedPaths.add(entity.path);
          });
        }
      },
      onSelectionChanged: (val) => _toggleSelection(entity.path),
      onDragUpdate: _handleScrollOnDrag,
      onDragEnd: _stopAutoScroll,
      dragData: isSelected ? _selectedPaths.toList() : [..._selectedPaths, entity.path],
      feedback: _buildFeedback(entity, name, isSelected, fontSize, ViewMode.grid), // re-use grid feedback
      isDraggingDisabled: (_isMovingMode || _selectionMode == 'move') && entity is! Directory && !isMovingTarget,
      child: squareContent,
    );

    return isDir ? _buildDragTarget(entity, itemTile) : itemTile;
  }

  // --- Helper Methods to reduce duplication ---

  Widget _buildDragTarget(FileSystemEntity entity, Widget child) {
    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (details) => !details.data.contains(entity.path),
      onAcceptWithDetails: (details) => _moveItems(details.data, entity.path),
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty;
        return Stack(
          children: [
            child,
            if (isDraggingOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.blue, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMoveLabel(double fontSize, {bool isGrid = false, bool isSquare = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSquare ? 8 : 6, vertical: isSquare ? 4 : 2),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(isSquare ? 10 : (isGrid ? 6 : 0)),
          bottomLeft: Radius.circular(isSquare ? 10 : (isGrid ? 6 : 6)),
          bottomRight: Radius.circular(isGrid || isSquare ? 0 : 6),
        ),
      ),
      child: Text(
        "move_prepare".tr(),
        style: TextStyle(color: Colors.white, fontSize: isSquare ? 10 : 8, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFeedback(FileSystemEntity entity, String name, bool isSelected, double fontSize, ViewMode mode) {
    final double width = mode == ViewMode.list ? 250 : 180;
    return Material(
      elevation: mode == ViewMode.list ? 12 : 16,
      borderRadius: BorderRadius.circular(mode == ViewMode.list ? 8 : 12),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).cardColor.withValues(alpha: mode == ViewMode.list ? 0.95 : 0.9),
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, decoration: TextDecoration.none),
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue.withValues(alpha: 0.5), width: 1.5),
              borderRadius: BorderRadius.circular(mode == ViewMode.list ? 8 : 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FileThumbnail(
                  file: entity, 
                  size: fontSize.iMedium * (mode == ViewMode.list ? 1.5 : 1.0), 
                  iconSize: fontSize.fHeader, 
                  borderRadius: BorderRadius.circular(6)
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (_selectedPaths.length + (isSelected ? 0 : 1)) > 1
                        ? "move_confirm_message".tr(args: [(_selectedPaths.length + (isSelected ? 0 : 1)).toString()])
                        : name,
                    style: TextStyle(fontSize: fontSize.fBody * 0.9, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasParent = !widget.isRecentFilesMode && 
                    _currentDirectory != null && 
                    _rootDirectory != null && 
                    _currentDirectory!.path != _rootDirectory!.path;
    final fontSize = context.watch<FontSizeProvider>().getScaledSize(16);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop) {
          if (!mounted) return;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(fontSize),
        bottomNavigationBar: _isMovingMode ? _buildMoveBottomBar(fontSize) : null,
        body: SafeArea(
          child: GestureDetector(
          onTap: _clearSelection,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              if (!widget.isRecentFilesMode && _categoryTitle == null)
                Container(
                  key: ValueKey("filter_$fontSize"),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).appBarTheme.backgroundColor,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('image', Icons.image, 'filter_image'.tr(), Colors.pink, fontSize),
                        _buildFilterChip('video', Icons.play_circle_fill, 'filter_video'.tr(), Colors.purple, fontSize),
                        _buildFilterChip('audio', Icons.audiotrack, 'filter_audio'.tr(), Colors.blue, fontSize),
                        _buildFilterChip('document', Icons.description, 'filter_document'.tr(), Colors.orange, fontSize),
                      ],
                    ),
                  ),
                ),
              _buildSortAndViewControls(fontSize),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 230),
                  transitionBuilder: AnimatedSwitcher.defaultTransitionBuilder,
                  child: _isLoading 
                    ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
                    : _filteredFiles.isEmpty && !hasParent
                      ? Center(key: const ValueKey('empty'), child: Text("empty_folder".tr()))
                      : Scrollbar(
                          key: ValueKey(_currentDirectory?.path ?? 'root'),
                          controller: _scrollController,
                          thumbVisibility: false,
                          trackVisibility: false,
                          interactive: true,
                          thickness: 12.0,
                          radius: const Radius.circular(6),
                          child: Container(
                            key: _scrollableKey,
                            child: _config.viewMode == ViewMode.list
                            ? GestureDetector(
                                onTap: _clearSelection,
                                behavior: HitTestBehavior.opaque,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: _filteredFiles.length + (hasParent ? 1 : 0),
                                    itemBuilder: (ctx, i) {
                                      if (hasParent && i == 0) return _buildParentTile(ViewMode.list, fontSize);
                                      return _buildListTile(i, fontSize, hasParent);
                                    },
                                ),
                              )
                            : (() {
                                final folders = _filteredFiles.where((item) => item.entity is Directory).map((item) => item.entity).toList();
                                final files = _filteredFiles.where((item) => item.entity is File).map((item) => item.entity).toList();
                                
                                return GestureDetector(
                                  onTap: _clearSelection,
                                  behavior: HitTestBehavior.opaque,
                                  child: CustomScrollView(
                                    controller: _scrollController,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    slivers: [
                                      if (folders.isNotEmpty || hasParent)
                                        SliverPadding(
                                          padding: const EdgeInsets.all(8),
                                          sliver: SliverGrid(
                                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 2,
                                              childAspectRatio: 4.8,
                                              crossAxisSpacing: 4, // Reduced from 8
                                              mainAxisSpacing: 4, // Reduced from 8
                                            ),
                                            delegate: SliverChildBuilderDelegate(
                                              (ctx, i) {
                                                if (hasParent && i == 0) return _buildParentTile(ViewMode.grid, fontSize);
                                                final folderIndex = hasParent ? i - 1 : i;
                                                return _buildGridTile(folders[folderIndex], fontSize: fontSize);
                                              },
                                              childCount: folders.length + (hasParent ? 1 : 0),
                                            ),
                                          ),
                                        ),
                                      if (files.isNotEmpty)
                                        SliverPadding(
                                          padding: const EdgeInsets.all(8),
                                          sliver: SliverGrid(
                                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 2,
                                              childAspectRatio: 1.0,
                                              crossAxisSpacing: 6, // Reduced from 10
                                              mainAxisSpacing: 6, // Reduced from 10
                                            ),
                                            delegate: SliverChildBuilderDelegate(
                                              (ctx, i) => _buildSquareTile(files[i], fontSize),
                                              childCount: files.length,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }()),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildSortAndViewControls(double fontSize) {
    String sortText = "";
    switch (_config.sortType) {
      case SortType.name: sortText = "sort_name".tr(); break;
      case SortType.date: sortText = "sort_date".tr(); break;
      case SortType.type: sortText = "sort_type".tr(); break;
      case SortType.size: sortText = "sort_size".tr(); break;
    }


    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          // Left: View Mode Toggle Button
          IconButton(
            onPressed: () => setState(() => _config.viewMode = _config.viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list),
            icon: Icon(
              _config.viewMode == ViewMode.list ? Icons.grid_view : Icons.view_list,
              size: fontSize.iMedium,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: _config.viewMode == ViewMode.list ? 'grid_view'.tr() : 'list_view'.tr(), // grid_view / list_view tooltips are not in JSON yet, I'll add them or use generic names
          ),
          const Spacer(),
          // Right: Sort Controls
          InkWell(
            onTap: () {
              setState(() {
                final values = SortType.values;
                final currentIndex = values.indexOf(_config.sortType);
                _config.sortType = values[(currentIndex + 1) % values.length];
                _applyFiltersAndSort();
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort, size: fontSize.iSmall, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  sortText,
                  style: TextStyle(fontSize: fontSize.fSmall, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(height: 12, width: 1, color: Colors.grey[300]),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _config.sortOrder = _config.sortOrder == SortOrder.ascending ? SortOrder.descending : SortOrder.ascending;
                _applyFiltersAndSort();
              });
            },
            child: Icon(
              _config.sortOrder == SortOrder.ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: fontSize.iSmall,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String type, IconData icon, String label, Color color, double fontSize) {
    final isSelected = _typeFilter.contains(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (isSelected) {
                _typeFilter.remove(type);
              } else {
                _typeFilter.add(type);
              }
              _applyFiltersAndSort();
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : Theme.of(context).appBarTheme.backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : Theme.of(context).dividerColor.withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: fontSize.iSmall, color: isSelected ? color : color.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize.fBody,
                    color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _clearSelection() {
    if (_isSelectionMode) {
      setState(() {
        _isSelectionMode = false;
        _selectionMode = null;
        _selectedPaths.clear();
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("dialog_delete_title".tr()),
        content: Text("dialog_delete_message".tr(args: [_selectedPaths.length.toString()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('action_cancel'.tr())),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: Text("action_move".tr()) // reused 'move' for '?대룞'
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _logic.deleteItems(_selectedPaths.toList());
      
      setState(() {
        _selectedPaths.clear();
        _isSelectionMode = false;
      });
      
      if (widget.isRecentFilesMode) {
        _performGlobalSearch(_searchQuery);
      } else {
        _listDirectory();
      }
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("items_deleted_count".tr())));
      }
    }
  }

  Future<void> _createNewFolder() async {
    if (_currentDirectory == null) return;
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("dialog_create_folder_title".tr()),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(hintText: "dialog_create_folder_hint".tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("action_cancel".tr())),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final newPath = p.join(_currentDirectory!.path, name);
              if (Directory(newPath).existsSync()) {
                if (mounted) {
                  await showDialog(
                    context: context,
                    builder: (alertCtx) => AlertDialog(
                      title: Text("error_folder_exists_title".tr()),
                      content: Text("error_folder_exists_message".tr()),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(alertCtx),
                          child: Text("action_confirm".tr()),
                        ),
                      ],
                    ),
                  );
                }
                return; // Keep the creation dialog open
              }

              final success = await _logic.createNewFolder(_currentDirectory!.path, name);
              if (mounted) {
                if (success) {
                  Navigator.pop(ctx);
                  _listDirectory();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("error_folder_create".tr())));
                }
              }
            },
            child: Text("action_confirm".tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _permanentDeleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("dialog_perm_delete_title".tr()),
        content: Text("dialog_perm_delete_message".tr(args: [_selectedPaths.length.toString()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("action_cancel".tr())),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("action_permanent_delete".tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _logic.permanentDeleteItems(_selectedPaths.toList());
      
      setState(() {
        _selectedPaths.clear();
        _isSelectionMode = false;
      });
      if (widget.isRecentFilesMode) {
        _performGlobalSearch(_searchQuery);
      } else {
        _listDirectory();
      }
    }
  }

  Future<void> _completeMoving() async {
    if (_pathsToMove.isEmpty || _currentDirectory == null) return;
    
    await _moveItems(_pathsToMove, _currentDirectory!.path);
    setState(() {
      _isMovingMode = false;
      _pathsToMove = [];
    });
  }

  void _cancelMoving() {
    setState(() {
      _isMovingMode = false;
      _pathsToMove = [];
    });
  }

  Future<void> _moveSelected() async {
    if (_selectedPaths.isEmpty) return;
    
    setState(() {
      _pathsToMove = _selectedPaths.toList();
      _isMovingMode = true;
      _isSelectionMode = false;
      _selectionMode = null;
      _selectedPaths.clear();
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("move_instruction".tr()))
    );
  }

  Widget _buildMoveBottomBar(double fontSize) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _completeMoving,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text("move_here".tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }
}

// --- Workers removed and moved to FileOperationLogic ---
