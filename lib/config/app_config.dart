class AppConfig {
  // Feature toggles
  static const bool enableTrash = true;         // 휴지통 기능
  static const bool enableFileOpen = true;      // 파일 열기
  static const bool enableDragDrop = true;      // 드래그 앤 드롭
  static const bool enableFolderCreate = true;  // 폴더 생성
  
  // diy_workbook으로 복사 시:
  // enableTrash = false 로 변경하면 휴지통 기능 비활성화
}
