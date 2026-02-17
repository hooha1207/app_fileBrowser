import 'dart:io';
import 'package:flutter/material.dart';
import 'package:app_filepicker/core/trash_manager.dart';
import 'package:path/path.dart' as p;
import 'package:app_filepicker/core/file_picker_config.dart';
import 'package:app_filepicker/providers/font_provider.dart';
import 'package:provider/provider.dart';
import 'package:app_filepicker/core/localization.dart';
import 'package:intl/intl.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

enum TrashAction { restore, permanentDelete }

class _TrashScreenState extends State<TrashScreen> {
  final TrashManager _trashManager = TrashManager();
  bool _isLoading = false;
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  TrashAction? _currentAction;
  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _isLoading = true);
    await _trashManager.init();
    setState(() => _isLoading = false);
  }

  String _formatDate(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
          _currentAction = null;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _startSelectionMode(TrashAction action) {
    setState(() {
      _isSelectionMode = true;
      _currentAction = action;
      _selectedIds.clear();
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _currentAction = null;
      _selectedIds.clear();
    });
  }

  Future<void> _executeAction() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("error_select_items".tr())) // I need to add this to JSON or use select_hint
      );
      return;
    }

    if (_currentAction == TrashAction.restore) {
      await _restoreSelected();
    } else if (_currentAction == TrashAction.permanentDelete) {
      await _deleteSelectedPermanently();
    }
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("action_restore".tr()),
        content: Text("confirm_restore_selected".tr(namedArgs: {'count': '${_selectedIds.length}'})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("action_cancel".tr())),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("action_trash".tr())),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      for (var id in _selectedIds.toList()) {
        final item = _trashManager.items.firstWhere((e) => e.id == id);
        await _trashManager.restore(item);
      }
      setState(() {
        _isLoading = false;
        _selectedIds.clear();
        _isSelectionMode = false;
        _currentAction = null;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("msg_restored".tr())));
    }
  }

  Future<void> _deleteSelectedPermanently() async {
    if (_selectedIds.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("action_delete_perm".tr()),
        content: Text("confirm_delete_perm_selected".tr(namedArgs: {'count': '${_selectedIds.length}'})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("action_cancel".tr())),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("action_delete".tr()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      for (var id in _selectedIds.toList()) {
        final item = _trashManager.items.firstWhere((e) => e.id == id);
        await _trashManager.deletePermanently(item);
      }
      setState(() {
        _isLoading = false;
        _selectedIds.clear();
        _isSelectionMode = false;
        _currentAction = null;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("msg_deleted_perm".tr())));
    }
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text("action_empty_trash".tr()),
         content: Text("confirm_empty_trash".tr()),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("action_cancel".tr())),
           TextButton(
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             onPressed: () => Navigator.pop(ctx, true), 
             child: Text("action_delete".tr())
           ),
         ],
      ),
    );
    
    if (confirm == true) {
      setState(() => _isLoading = true);
      await _trashManager.emptyTrash();
      setState(() {
        _isLoading = false;
        _selectedIds.clear();
        _isSelectionMode = false;
        _currentAction = null;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("msg_trash_emptied".tr())));
    }
  }

  void _showMeatballMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text("action_restore".tr()),
              onTap: () {
                Navigator.pop(ctx);
                _startSelectionMode(TrashAction.restore);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text("action_delete_perm".tr(), style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _startSelectionMode(TrashAction.permanentDelete);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = context.watch<FontSizeProvider>().getScaledSize(16);
    final items = _trashManager.items;
    final sortedItems = List<TrashItem>.from(items)..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode 
          ? IconButton(
              icon: Icon(Icons.close, size: fontSize.iLarge),
              onPressed: _cancelSelection,
            )
          : IconButton(
              icon: Icon(Icons.arrow_back, size: fontSize.iLarge),
              onPressed: () => Navigator.pop(context),
            ),
        title: Text(_isSelectionMode 
          ? 'items_selected'.tr(args: ['${_selectedIds.length}'])
          : "utility_trash".tr()),
        actions: [
          if (!_isSelectionMode) ...[
            if (items.isNotEmpty)
              TextButton(
                onPressed: _emptyTrash, 
                child: Text("action_empty_trash".tr(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
              ),
            IconButton(
              icon: Icon(Icons.more_vert, size: fontSize.iLarge),
              onPressed: _showMeatballMenu,
              tooltip: "menu_tooltip".tr(),
            ),
          ],
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : sortedItems.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: fontSize.iHuge, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text("msg_trash_empty".tr(), style: TextStyle(color: Colors.grey, fontSize: fontSize.fBody)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: sortedItems.length,
              itemBuilder: (ctx, i) {
                final item = sortedItems[i];
                final isSelected = _selectedIds.contains(item.id);
                final isDir = FileSystemEntity.isDirectorySync(item.trashPath) || p.extension(item.fileName).isEmpty;

                return ListTile(
                  leading: _isSelectionMode
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (v) => _toggleSelection(item.id),
                      )
                    : Icon(isDir ? Icons.folder : Icons.insert_drive_file, color: Colors.grey, size: fontSize.iMedium),
                  title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fontSize.fBody)),
                  subtitle: Text("msg_deleted_at".tr(namedArgs: {'date': _formatDate(item.deletedAt)}), style: TextStyle(fontSize: fontSize.fSmall)),
                  selected: isSelected,
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(item.id);
                    }
                  },
                );
              },
            ),
      bottomNavigationBar: _isSelectionMode
        ? Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: _executeAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _currentAction == TrashAction.permanentDelete 
                    ? Colors.red 
                    : Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _currentAction == TrashAction.restore ? "action_restore".tr() : "action_delete_perm".tr(),
                  style: TextStyle(fontSize: fontSize.fBody, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
        : null,
    );
  }
}
