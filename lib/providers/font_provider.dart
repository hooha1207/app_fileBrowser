import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontSizeProvider with ChangeNotifier {
  static const String _fontKey = 'font_scale';
  static const List<double> availableScales = [0.8, 0.9, 1.0, 1.1, 1.2, 1.4];
  
  double _scaleFactor = 1.0;

  double get scaleFactor => _scaleFactor;

  FontSizeProvider() {
    _loadScale();
  }

  void _loadScale() async {
    final prefs = await SharedPreferences.getInstance();
    _scaleFactor = prefs.getDouble(_fontKey) ?? 1.0;
    if (!availableScales.contains(_scaleFactor)) {
      _scaleFactor = 1.0;
    }
    notifyListeners();
  }

  Future<void> setScale(double scale) async {
    if (!availableScales.contains(scale)) return;
    _scaleFactor = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontKey, scale);
  }

  double getScaledSize(double baseSize) {
    return (baseSize * _scaleFactor).floorToDouble();
  }
}
