# 구현 계획서 (Implementation Plan) - 보완됨

## 목표 구체화
현재 코드베이스(`app_filePicker`)의 코드를 점검하고, 중복되거나 불필요한 코드를 정리하며, 로컬라이제이션(Localization) 시스템을 일원화합니다. 추가적으로 `REFACTORING_GUIDE.md`를 바탕으로 `BrowserScreen`의 비대한 코드를 정리하고 공통 UI 위젯을 추출하여 재사용성과 유지보수성을 높입니다.

## 사용자 검토 필요 사항 (User Review Required)
> [!IMPORTANT]
> `BrowserScreen`의 코드가 1,700라인을 넘어가므로, 타일 생성 로직(`ListTile`, `GridTile`, `SquareTile`)에서 공통으로 사용되는 선택(Selection), 드래그 앤 드롭(Drag & Drop) 로직을 `FileItemTile` 위젯으로 추출할 예정입니다.

## Proposed Changes

### 1. 전역 시스템 정리
#### [MODIFY] [main.dart](file:///f:/DIYworkbook/dev_app001/app_filePicker/lib/main.dart)
- 불필요한 주석 제거 및 코드 가용성 확인.

### 2. BrowserScreen 최적화 및 위젯 추출
#### [NEW] [file_item_tile.dart](file:///f:/DIYworkbook/dev_app001/app_filePicker/lib/widgets/file_item_tile.dart)
- `ListTile`, `GridTile`, `SquareTile`에서 공통으로 사용하는 로직(선택 체크박스, 드래그 앤 드롭, 하이라이트 효과)을 담당하는 래퍼 위젯 구현.

#### [MODIFY] [browser_screen.dart](file:///f:/DIYworkbook/dev_app001/app_filePicker/lib/screens/browser_screen.dart)
- `_buildListTile`, `_buildGridTile`, `_buildSquareTile` 내부의 복잡한 로직을 `FileItemTile`로 교체.
- 중복되는 `buildDraggable`, `wrapWithCheckbox` 헬퍼 메서드 제거.

### 3. 로컬라이제이션 일원화
- 현재 사용 중인 커스텀 `AppLocalization` 클래스를 유지하되, `easy_localization` 관련 잔재가 없는지 최종 확인 후 정리. (분류 완료)

## Verification Plan

### Automated Tests
- `flutter analyze` 명령어를 실행하여 코드 분석 오류가 없는지 확인.

### Manual Verification
- **UI 일관성 확인**: 리스트, 그리드, 스퀘어 뷰 모드에서 선택 및 드래그 기능이 리팩토링 전과 동일하게 작동하는지 확인.
- **다크 모드**: 테마 변경 시 `FileItemTile`의 하이라이트 및 체크박스 색상이 올바르게 적용되는지 확인.
- **기능 확인**: 파일 탐색, 폴더 생성, 삭제, 이동 등 주요 기능 동작 확인.
