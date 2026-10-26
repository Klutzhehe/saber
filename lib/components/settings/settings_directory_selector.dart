import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/font_fallbacks.dart';

class SettingsDirectorySelector extends StatelessWidget {
  const new({
    super.key,
    required this.title,
    required this.icon,
    this.afterChange,
    this.isUnsupported = false,
  });

  final String title;
  final IconData icon;
  final ValueChanged<Color?>? afterChange;
  final bool isUnsupported;

  void onPressed(BuildContext context) async {
    if (Platform.isAndroid) {
      await FileManager.requestStoragePermission();
    }
    if (!context.mounted) return;
    await showAdaptiveDialog(
      context: context,
      builder: (context) => DirectorySelector(
        title: title,
        initialDirectory: FileManager.documentsDirectory,
        mustBeEmpty: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onPressed(context),
      child: ListTile(
        contentPadding: const .symmetric(vertical: 4, horizontal: 16),
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: Icon(icon, key: ValueKey(icon)),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontStyle:
                stows.customDataDir.value != stows.customDataDir.defaultValue
                ? FontStyle.italic
                : null,
          ),
        ),
        subtitle: ValueListenableBuilder(
          valueListenable: stows.customDataDir,
          builder: (context, _, _) => Text(
            FileManager.documentsDirectory,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class DirectorySelector extends StatefulWidget {
  const new({
    super.key,
    required this.title,
    required this.initialDirectory,
    this.mustBeEmpty = false,
    this.mustBeDoneSyncing = true,
  });

  final String title;
  final String initialDirectory;
  final bool mustBeEmpty;
  final bool mustBeDoneSyncing;

  @override
  State<DirectorySelector> createState() => _DirectorySelectorState();
}

class _DirectorySelectorState extends State<DirectorySelector> {
  late String _directory = widget.initialDirectory;
  late var _isEmpty = true;

  Future<void> _pickDir() async {
    if (Platform.isAndroid) {
      await FileManager.requestStoragePermission();
    }

    String? directory;
    try {
      directory = await FilePicker.getDirectoryPath(
        dialogTitle: widget.title,
        initialDirectory: _directory,
        androidOptions: defaultTargetPlatform == .android
            ? const FilePickerAndroidOptions(
                safOptions: .new(
                  grant: .lifetime,
                  accessMode: .readWrite,
                  persistGrant: true,
                ),
              )
            : const .new(),
      );
    } catch (_) {
      try {
        directory = await FilePicker.getDirectoryPath(
          dialogTitle: widget.title,
          initialDirectory: _directory,
        );
      } catch (_) {}
    }

    if (directory == null) return;
    if (directory == _directory) return;

    final dir = Directory(directory);
    _directory = directory;
    try {
      _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;
    } catch (_) {
      _isEmpty = false;
    }

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _pickDefaultDir() async {
    final directory = await FileManager.getDefaultDocumentsDirectory();

    final dir = Directory(directory);
    _directory = directory;
    try {
      _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;
    } catch (_) {
      _isEmpty = true;
    }

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onConfirm() async {
    final defaultDir = await FileManager.getDefaultDocumentsDirectory();
    if (_directory == defaultDir) {
      stows.customDataDir.value = null;
    } else {
      stows.customDataDir.value = _directory;
    }
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final emptyError = widget.mustBeEmpty && !_isEmpty;
    final syncingError =
        widget.mustBeDoneSyncing &&
        (syncer.uploader.numPending > 0 || syncer.downloader.numPending > 0);
    final anyErrors = emptyError || syncingError;

    return AdaptiveAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: .min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _directory,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'FiraMono',
                    fontFamilyFallback: saberMonoFontFallbacks,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.folder), onPressed: _pickDir),
              if (stows.customDataDir.value != null)
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _pickDefaultDir,
                ),
            ],
          ),
          if (emptyError)
            Text(
              t.settings.customDataDir.mustBeEmpty,
              style: TextStyle(color: colorScheme.error),
            ),
          if (syncingError)
            Text(
              t.settings.customDataDir.mustBeDoneSyncing,
              style: TextStyle(color: colorScheme.error),
            ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => context.pop(),
          child: Text(t.settings.customDataDir.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: anyErrors ? null : _onConfirm,
          child: Text(t.settings.customDataDir.select),
        ),
      ],
    );
  }
}
