# App FilePicker (File Browser Project)

Developed with Antigravity.

A file browser and picker application built with Flutter. It's designed to provide a user-friendly interface with features like drag-and-drop, versatile view modes, and font scaling.

## Key Features

- **Multiple View Modes**: Supports List, Grid, and Square modes with transitions.
- **Drag & Drop**: Long-press items to drag, with automatic scrolling when reaching screen edges.
- **Dedicated Selection Modes**: Includes Select, Move, and Delete modes for various workflows.
- **Material Design Touch Feedback**: Implements the Material + Ink + InkWell pattern for ripple effects across themes.
- **Accessibility-Focused Font Scaling**: Built-in system that scales the UI (text, icons, spacing) based on user settings.
- **Search & Sorting**: Real-time search filtering and sorting by name, date, type, or size.
- **File Operations**: Support for creating folders, moving, deleting, and opening files (using `open_filex`).
- **Dark Mode Support**: Adapts to system-wide light and dark themes.

## Screenshots

Showcasing the core features and UI of the application, designed with Material 3 guidelines.

### Hero Dashboard
<p align="center">
  <img src="./images/screen_home.png" width="45%" alt="Main Dashboard" />
  <br>
  <i>The main screen providing an overview of internal storage, file categories, and recent activity.</i>
</p>

---

### Folder Navigation
<p align="center">
  <img src="./images/screen_folder.png" width="45%" alt="Folder Navigation" />
  <br>
  <i>Folder navigation with support for various view modes.</i>
</p>

---

### Core Operations
Handle folder creation and deletions with interactive dialogs.

| New Folder | Delete Confirmation |
| :---: | :---: |
| <img src="./images/screen_createFolder.png" height="500" /> | <img src="./images/screen_delete.png" height="500" /> |
| **Material 3** styled input dialog | **Safety-first** deletion system with confirmation |

---

### Utilities & Specialized Views
Additional tools for streamlined file management.

| Recent Files | Trash (Recycle Bin) |
| :---: | :---: |
| <img src="./images/screen_recent.png" height="500" /> | <img src="./images/screen_trash.png" height="500" /> |
| Quick access to recently added files | Securely store and restore deleted items |

## Tech Stack

- **Framework**: Flutter
- **State Management**: Provider
- **Local Storage**: Shared Preferences
- **Key Packages**:
  - `path_provider`: For local path access.
  - `permission_handler`: For managing permissions.
  - `intl`: For localization and date formatting.
  - `open_filex`: For opening files.

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone [your-repository-url]
   ```

2. **Initialize Project**:
   On Windows, use the provided batch file to set up the environment easily.
   ```bash
   ./init_flutter_project.bat
   ```

3. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

4. **Run the App**:
   ```bash
   flutter run
   ```

## Architecture & Design Guides

The project follows core design patterns for maintainability:

- **Ink Widget Pattern**: All interactive elements use `Material` + `Ink` + `InkWell` to guarantee visual feedback.
- **Font Scaling Extension**: Uses custom extensions on `double` to scale font sizes, icons, and spacing proportionally.
- **Clean Widget Extraction**: Business logic and complex UI are decoupled into standalone widgets (e.g., `FileItemTile`).

## License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.

## Contact

For questions or feedback, please contact:
- **Email**: [hooha1207@gmail.com](mailto:hooha1207@gmail.com)
