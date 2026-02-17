enum FileType { image, video, audio, document, download, apk }

class FileFormats {
  static const Map<String, List<String>> extensions = {
    'image': [
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', 
      '.svg', '.heic', '.tiff', '.ico', '.raw', '.dng'
    ],
    'video': [
      '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', 
      '.webm', '.3gp', '.m4v', '.ts', '.ogv'
    ],
    'audio': [
      '.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg', 
      '.wma', '.alac', '.aiff', '.mid', '.midi'
    ],
    'document': [
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', 
      '.txt', '.md', '.rtf', '.csv', '.json', '.xml', '.hwp', '.odt'
    ],
    'apk': ['.apk'],
  };
}
