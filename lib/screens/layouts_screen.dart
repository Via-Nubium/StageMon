import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/mixer_layout_state.dart';
import '../models/saved_layout.dart';

class LayoutsScreen extends StatefulWidget {
  final MixerLayoutState layout;
  final String consoleModel;
  // Set when this screen was opened automatically because a .stagemonlayout
  // file arrived via Android's "Open with" while disconnected/elsewhere in
  // the app — see LayoutImportService. Runs the same import+load flow as
  // tapping the file-picker button, just with the content already in hand.
  final String? initialImportContent;

  const LayoutsScreen({
    super.key,
    required this.layout,
    required this.consoleModel,
    this.initialImportContent,
  });

  @override
  State<LayoutsScreen> createState() => _LayoutsScreenState();
}

class _LayoutsScreenState extends State<LayoutsScreen> {
  final LayoutManager _manager = LayoutManager();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _manager.load().then((_) async {
      if (!mounted) return;
      setState(() => _loaded = true);
      final pending = widget.initialImportContent;
      if (pending != null) await _applyImportedContent(pending);
    });
  }

  SavedLayout _currentAsLayout(String name, {required bool includeBus}) =>
      SavedLayout(
        name: name,
        console: widget.consoleModel,
        bus: includeBus ? widget.layout.bus : null,
        layout: widget.layout,
      );

  Future<(String, bool)?> _showNameDialog({
    required String defaultName,
    bool showBusOption = false,
    bool initialIncludeBus = true,
  }) {
    return showDialog<(String, bool)>(
      context: context,
      builder: (_) => _LayoutNameDialog(
        defaultName: defaultName,
        showBusOption: showBusOption,
        initialIncludeBus: initialIncludeBus,
      ),
    );
  }

  Future<void> _saveCurrent() async {
    final l = AppLocalizations.of(context)!;
    final result = await _showNameDialog(
      defaultName: l.layoutDefaultName(_manager.layouts.length + 1),
      showBusOption: true,
    );
    if (result == null) return;
    final (name, includeBus) = result;
    if (name.isEmpty) return;
    await _manager.add(_currentAsLayout(name, includeBus: includeBus));
    if (mounted) setState(() {});
  }

  Future<void> _loadLayout(SavedLayout layout) async {
    final l = AppLocalizations.of(context)!;
    final busWillChange = layout.bus != null && layout.bus != widget.layout.bus;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.loadLayoutConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.loadLayoutConfirm(layout.name)),
            if (busWillChange) ...[
              const SizedBox(height: 8),
              Text(
                l.busWillChangeNote,
                style: const TextStyle(
                  color: Color(0xFFE3A73B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(l.load),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, layout);
  }

  // Written to the app's own temp dir (no storage permission needed) and
  // handed to Android's share sheet, so the receiving device can pick it up
  // however it likes (chat app, Drive, Bluetooth...). Extension is custom so
  // the file is easy to tell apart from unrelated .json files when the
  // receiving device later opens it with a file picker.
  Future<void> _shareLayout(SavedLayout layout) async {
    final dir = await getTemporaryDirectory();
    final safeName = layout.name.trim().replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final file = File('${dir.path}/$safeName.stagemonlayout');
    await file.writeAsString(jsonEncode(layout.toJson()));
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: layout.name),
    );
  }

  // FileType.any rather than filtering by our custom extension: Android maps
  // an unregistered extension to an unpredictable MIME type, which can make
  // the system picker hide files that don't declare that exact MIME instead
  // of filtering by extension. Content is validated after picking instead.
  Future<void> _importLayout() async {
    final result = await FilePicker.pickFiles(type: FileType.any);
    final path = result?.files.single.path;
    if (path == null) return;
    String raw;
    try {
      raw = await File(path).readAsString();
    } catch (_) {
      // Not valid text (e.g. a binary file) — pass through so
      // _applyImportedContent's own error handling shows the same dialog.
      raw = '';
    }
    await _applyImportedContent(raw);
  }

  // Shared by the manual file-picker import and by a file opened via
  // Android's "Open with" (LayoutImportService) — same validation, same
  // add-then-offer-to-load flow either way.
  Future<void> _applyImportedContent(String raw) async {
    final l = AppLocalizations.of(context)!;
    try {
      final json = jsonDecode(raw);
      final layout = SavedLayout.fromJson(json as Map<String, dynamic>);
      await _manager.add(layout);
      if (!mounted) return;
      setState(() {});
      await _loadLayout(layout);
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l.importErrorTitle),
          content: Text(l.importErrorBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(l.ok)),
          ],
        ),
      );
    }
  }

  Future<void> _showActionsMenu(int index) async {
    final l = AppLocalizations.of(context)!;
    final layout = _manager.layouts[index];
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (d) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  layout.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(l.saveLayout),
                onTap: () => Navigator.pop(d, 'overwrite'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.rename),
                onTap: () => Navigator.pop(d, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(l.share),
                onTap: () => Navigator.pop(d, 'share'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  l.delete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(d, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'overwrite') {
      final includeBus = await showDialog<bool>(
        context: context,
        builder: (d) => _OverwriteLayoutDialog(
          layoutName: layout.name,
          initialIncludeBus: layout.bus != null,
        ),
      );
      if (includeBus != null) {
        await _manager.overwrite(
          index,
          _currentAsLayout(layout.name, includeBus: includeBus),
        );
        if (mounted) setState(() {});
      }
    } else if (action == 'share') {
      await _shareLayout(layout);
    } else if (action == 'delete') {
      await _manager.remove(index);
      if (mounted) setState(() {});
    } else if (action == 'rename') {
      final result = await _showNameDialog(defaultName: layout.name);
      if (result != null && result.$1.isNotEmpty) {
        await _manager.rename(index, result.$1);
        if (mounted) setState(() {});
      }
    }
  }

  String _layoutSummary(AppLocalizations l, SavedLayout saved) {
    final parts = [
      l.channelCount(saved.channelCount),
      if (saved.hasLineIn) l.lineIn,
      if (saved.fxReturnCount > 0) l.fxReturnCount(saved.fxReturnCount),
      if (saved.visibleGroupCount > 0) l.groupCount(saved.visibleGroupCount),
      if (saved.bus != null) l.busTitleMono(saved.bus!),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.layoutsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: l.importLayout,
            onPressed: _importLayout,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l.saveCurrentState,
            onPressed: _saveCurrent,
          ),
        ],
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : _manager.layouts.isEmpty
          ? Center(child: Text(l.noLayoutsSaved))
          : ListView.separated(
              itemCount: _manager.layouts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final layout = _manager.layouts[i];
                return ListTile(
                  title: Text(layout.name),
                  subtitle: Text(
                    _layoutSummary(l, layout),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _loadLayout(layout),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    tooltip: l.layoutActionsTooltip,
                    onPressed: () => _showActionsMenu(i),
                  ),
                );
              },
            ),
    );
  }
}

class _LayoutNameDialog extends StatefulWidget {
  final String defaultName;
  final bool showBusOption;
  final bool initialIncludeBus;
  const _LayoutNameDialog({
    required this.defaultName,
    this.showBusOption = false,
    this.initialIncludeBus = true,
  });

  @override
  State<_LayoutNameDialog> createState() => _LayoutNameDialogState();
}

class _LayoutNameDialogState extends State<_LayoutNameDialog> {
  late final TextEditingController _controller;
  late bool _includeBus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
    _includeBus = widget.initialIncludeBus;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _controller.text.trim();
    if (t.isNotEmpty) Navigator.pop(context, (t, _includeBus));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.layoutNameTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
              if (widget.showBusOption)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.includeBusOption),
                  value: _includeBus,
                  onChanged: (v) => setState(() => _includeBus = v ?? true),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                  TextButton(onPressed: _submit, child: Text(l.save)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverwriteLayoutDialog extends StatefulWidget {
  final String layoutName;
  final bool initialIncludeBus;
  const _OverwriteLayoutDialog({
    required this.layoutName,
    required this.initialIncludeBus,
  });

  @override
  State<_OverwriteLayoutDialog> createState() => _OverwriteLayoutDialogState();
}

class _OverwriteLayoutDialogState extends State<_OverwriteLayoutDialog> {
  late bool _includeBus;

  @override
  void initState() {
    super.initState();
    _includeBus = widget.initialIncludeBus;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.saveLayout),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.overwriteLayoutConfirm(widget.layoutName)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.includeBusOption),
            value: _includeBus,
            onChanged: (v) => setState(() => _includeBus = v ?? true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _includeBus),
          child: Text(l.save),
        ),
      ],
    );
  }
}
