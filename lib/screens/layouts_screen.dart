import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/group_fader_config.dart';
import '../models/saved_layout.dart';

class LayoutsScreen extends StatefulWidget {
  final Set<int> selectedChannels;
  final bool showBusFader;
  final int bus;
  final List<GroupFaderConfig> groupConfigs;
  final Set<int> selectedFxReturns;
  final bool showLineIn;
  final bool busAlwaysVisible;
  final Map<int, int?> channelColors;
  final int? lineInColor;
  final Map<int, int?> fxReturnColors;
  final Map<int, int?> busColors;
  final String consoleModel;

  const LayoutsScreen({
    super.key,
    required this.selectedChannels,
    required this.showBusFader,
    required this.bus,
    required this.groupConfigs,
    required this.selectedFxReturns,
    required this.showLineIn,
    required this.busAlwaysVisible,
    required this.channelColors,
    required this.lineInColor,
    required this.fxReturnColors,
    required this.busColors,
    required this.consoleModel,
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
    _manager.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  SavedLayout _currentAsLayout(String name, {required bool includeBus}) =>
      SavedLayout(
        name: name,
        selectedChannels: Set.of(widget.selectedChannels),
        showBusFader: widget.showBusFader,
        bus: includeBus ? widget.bus : null,
        groupConfigs: List.of(widget.groupConfigs),
        selectedFxReturns: Set.of(widget.selectedFxReturns),
        showLineIn: widget.showLineIn,
        busAlwaysVisible: widget.busAlwaysVisible,
        channelColors: Map.of(widget.channelColors),
        lineInColor: widget.lineInColor,
        fxReturnColors: Map.of(widget.fxReturnColors),
        busColors: Map.of(widget.busColors),
        consoleModel: widget.consoleModel,
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
    final busWillChange = layout.bus != null && layout.bus != widget.bus;
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

  Future<void> _handleLongPress(int index) async {
    final l = AppLocalizations.of(context)!;
    final layout = _manager.layouts[index];
    final action = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(layout.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'overwrite'),
            child: Text(l.saveLayout),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'rename'),
            child: Text(l.rename),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'delete'),
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d),
            child: Text(l.cancel),
          ),
        ],
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

  String _layoutSummary(AppLocalizations l, SavedLayout layout) {
    final visibleGroups = layout.groupConfigs.where((g) => g.visible).length;
    final parts = [
      l.channelCount(layout.selectedChannels.length),
      if (layout.showLineIn) l.lineIn,
      if (layout.selectedFxReturns.isNotEmpty)
        l.fxReturnCount(layout.selectedFxReturns.length),
      if (visibleGroups > 0) l.groupCount(visibleGroups),
      if (layout.bus != null) l.busTitleMono(layout.bus!),
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
                  trailing: IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: l.loadLayoutTooltip,
                    onPressed: () => _loadLayout(layout),
                  ),
                  onLongPress: () => _handleLongPress(i),
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
