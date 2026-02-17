enum SortType { name, date, type, size }
enum SortOrder { ascending, descending }
enum ViewMode { list, grid }

class FilePickerConfig {
  SortType sortType;
  SortOrder sortOrder;
  ViewMode viewMode;
  
  // Auto-scroll settings for drag operations
  bool enableAutoScrollOnDrag;
  double autoScrollThreshold;
  double autoScrollMaxSpeed;

  FilePickerConfig({
    this.sortType = SortType.name,
    this.sortOrder = SortOrder.ascending,
    this.viewMode = ViewMode.grid,
    this.enableAutoScrollOnDrag = true,
    this.autoScrollThreshold = 60.0,
    this.autoScrollMaxSpeed = 15.0,
  });

  FilePickerConfig clone() {
    return FilePickerConfig(
      sortType: sortType,
      sortOrder: sortOrder,
      viewMode: viewMode,
      enableAutoScrollOnDrag: enableAutoScrollOnDrag,
      autoScrollThreshold: autoScrollThreshold,
      autoScrollMaxSpeed: autoScrollMaxSpeed,
    );
  }
}

extension FontSizeScaling on double {
  double get fTiny => this * 0.7;
  double get fSmall => this * 0.85;
  double get fBody => this;
  double get fHeader => this * 1.125;
  double get fLarge => this * 1.3;

  double get iSmall => this * 1.25;
  double get iMedium => this * 1.5;
  double get iLarge => this * 1.75;
  double get iHuge => this * 4.0;

  double get hSmall => this * 2.2;
  double get hMedium => this * 2.6;
  double get hLarge => this * 3.2;
}
