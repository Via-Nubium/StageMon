import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';

import '../models/snapshot_manager.dart';

/// The snapshots bottom sheet: save the current fader state under a name,
/// recall one, or rename/overwrite/delete an existing one.
///
/// It deliberately knows nothing about the mixer or its controller. Capturing
/// the current state and pushing a snapshot back out to the console both
/// belong to the mixer screen; this sheet only calls [captureCurrent] to get
/// something to store and [onRestore] to hand one back.
Future<void> showSnapshotsSheet({
  required BuildContext context,
  required SnapshotManager snapshots,
  required FaderSnapshot Function(String name) captureCurrent,
  required void Function(FaderSnapshot snapshot) onRestore,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _SnapshotsSheet(
      snapshots: snapshots,
      captureCurrent: captureCurrent,
      onRestore: onRestore,
    ),
  );
}

class _SnapshotsSheet extends StatefulWidget {
  const _SnapshotsSheet({
    required this.snapshots,
    required this.captureCurrent,
    required this.onRestore,
  });

  final SnapshotManager snapshots;
  final FaderSnapshot Function(String name) captureCurrent;
  final void Function(FaderSnapshot snapshot) onRestore;

  @override
  State<_SnapshotsSheet> createState() => _SnapshotsSheetState();
}

class _SnapshotsSheetState extends State<_SnapshotsSheet> {
  List<FaderSnapshot> get _snapshots => widget.snapshots.snapshots;

  Future<String?> _askForName({required String defaultName}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(defaultName: defaultName),
    );
  }

  Future<void> _saveNew() async {
    final l = AppLocalizations.of(context)!;
    final name = await _askForName(
      defaultName: l.snapshotDefaultName(_snapshots.length + 1),
    );
    if (name == null || name.isEmpty) return;
    await widget.snapshots.add(widget.captureCurrent(name));
    if (mounted) setState(() {});
  }

  Future<void> _showActions(int i) async {
    final l = AppLocalizations.of(context)!;
    final snap = _snapshots[i];
    final action = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(snap.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'overwrite'),
            child: Row(
              children: [
                const Icon(Icons.save_outlined),
                const SizedBox(width: 12),
                Text(l.saveSnapshot),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'rename'),
            child: Row(
              children: [
                const Icon(Icons.edit_outlined),
                const SizedBox(width: 12),
                Text(l.rename),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'delete'),
            child: Row(
              children: [
                const Icon(Icons.delete_outline, color: Colors.red),
                const SizedBox(width: 12),
                Text(l.delete, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d),
            child: Row(children: [const SizedBox(width: 36), Text(l.cancel)]),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'overwrite') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l.saveSnapshot),
          content: Text(l.overwriteSnapshotConfirm(snap.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(l.save),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.snapshots.overwrite(i, widget.captureCurrent(snap.name));
        if (mounted) setState(() {});
      }
    } else if (action == 'delete') {
      await widget.snapshots.remove(i);
      if (mounted) setState(() {});
    } else if (action == 'rename') {
      final name = await _askForName(defaultName: snap.name);
      if (name != null && name.isNotEmpty) {
        await widget.snapshots.rename(i, name);
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Text(
                    l.snapshotsTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.saveCurrentState),
                    onPressed: _saveNew,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_snapshots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(l.noSnapshotsSaved),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _snapshots.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final snap = _snapshots[i];
                    return ListTile(
                      title: Text(snap.name),
                      subtitle: Text(
                        snap.values.isEmpty
                            ? l.snapshotNoData
                            : l.snapshotChannels(snap.values.length),
                        style: TextStyle(
                          color: snap.values.isEmpty ? Colors.orange : null,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onRestore(snap);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: l.layoutActionsTooltip,
                        onPressed: () => _showActions(i),
                      ),
                      onLongPress: () => _showActions(i),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String defaultName;
  const _NameDialog({required this.defaultName});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
                l.snapshotNameTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isNotEmpty) Navigator.pop(context, t);
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l.cancel),
                  ),
                  TextButton(
                    onPressed: () {
                      final t = _controller.text.trim();
                      if (t.isNotEmpty) Navigator.pop(context, t);
                    },
                    child: Text(l.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
