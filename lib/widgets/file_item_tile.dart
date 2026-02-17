import 'dart:io';
import 'package:flutter/material.dart';


class FileItemTile extends StatelessWidget {
  final FileSystemEntity entity;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isMovingTarget;
  final bool hasHighlightAbove;
  final bool hasHighlightBelow;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Function(bool) onSelectionChanged;
  final Widget child;
  final Widget feedback;
  final void Function(Offset)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final bool isDraggingDisabled;
  final List<String>? dragData;

  const FileItemTile({
    super.key,
    required this.entity,
    required this.isSelected,
    required this.isSelectionMode,
    this.isMovingTarget = false,
    this.hasHighlightAbove = false,
    this.hasHighlightBelow = false,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectionChanged,
    required this.child,
    required this.feedback,
    this.onDragUpdate,
    this.onDragEnd,
    this.isDraggingDisabled = false,
    this.dragData,
  });

  @override
  Widget build(BuildContext context) {
    final isHighlighted = isSelected || isMovingTarget;

    Widget inkTile = Material(
      color: Colors.transparent,
      child: Ink(
        color: isHighlighted ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: isDraggingDisabled ? onLongPress : null,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              child,
              if (isHighlighted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: const BorderSide(color: Colors.blue, width: 2),
                          right: const BorderSide(color: Colors.blue, width: 2),
                          top: BorderSide(
                            color: (isHighlighted && hasHighlightAbove) ? Colors.transparent : Colors.blue,
                            width: 2,
                          ),
                          bottom: BorderSide(
                            color: (isHighlighted && hasHighlightBelow) ? Colors.transparent : Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (isDraggingDisabled) return inkTile;

    return LongPressDraggable<List<String>>(
      data: dragData ?? [entity.path],
      // Actually, the screen usually provides the data. Let's make it more flexible.
      // But for now, let's stick to what's needed for BrowserScreen.
      // In BrowserScreen, it was: isSelected ? _selectedPaths.toList() : [..._selectedPaths, entity.path]
      // That depends on the state of the screen. So the data should be passed in.
      axis: null,
      onDragStarted: onLongPress,
      onDragUpdate: (details) => onDragUpdate?.call(details.globalPosition),
      onDragEnd: (details) => onDragEnd?.call(),
      onDraggableCanceled: (velocity, offset) => onDragEnd?.call(),
      feedback: feedback,
      child: inkTile,
    );
  }
}
