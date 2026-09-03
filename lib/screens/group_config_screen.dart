import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../models/group_fader_config.dart';

class GroupConfigScreen extends StatefulWidget {
  final List<GroupFaderConfig> configs;
  final int groupIndex;
  final Map<int, String> channelNames;
  final Map<int, String> fxReturnNames;

  const GroupConfigScreen({
    super.key,
    required this.configs,
    required this.groupIndex,
    required this.channelNames,
    required this.fxReturnNames,
  });

  @override
  State<GroupConfigScreen> createState() => _GroupConfigScreenState();
}

class _GroupConfigScreenState extends State<GroupConfigScreen> {
  late List<GroupFaderConfig> _configs;

  GroupFaderConfig get _current => _configs[widget.groupIndex];

  @override
  void initState() {
    super.initState();
    _configs = widget.configs.map((c) => c.copyWith()).toList();
  }

  String _channelLabel(int ch) =>
      widget.channelNames[ch] ?? 'Ch ${ch.toString().padLeft(2, '0')}';

  String _fxReturnLabel(int rtn) =>
      widget.fxReturnNames[rtn] ?? 'FX $rtn';

  Future<void> _renameGroup() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _GroupNameDialog(defaultName: _current.name),
    );
    if (newName != null && mounted) {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(name: newName);
      });
    }
  }

  Future<void> _toggleChannel(int ch) async {
    if (_current.channels.contains(ch)) {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(
          channels: Set.of(_current.channels)..remove(ch),
        );
      });
      return;
    }

    int conflictIdx = -1;
    for (int i = 0; i < _configs.length; i++) {
      if (i != widget.groupIndex && _configs[i].channels.contains(ch)) {
        conflictIdx = i;
        break;
      }
    }

    if (conflictIdx != -1) {
      final confirmed = await _showReassignDialog(_channelLabel(ch), conflictIdx);
      if (confirmed != true) return;
      setState(() {
        _configs[conflictIdx] = _configs[conflictIdx].copyWith(
          channels: Set.of(_configs[conflictIdx].channels)..remove(ch),
        );
        _configs[widget.groupIndex] = _current.copyWith(
          channels: Set.of(_current.channels)..add(ch),
        );
      });
    } else {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(
          channels: Set.of(_current.channels)..add(ch),
        );
      });
    }
  }

  Future<void> _toggleFxReturn(int rtn) async {
    if (_current.fxReturns.contains(rtn)) {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(
          fxReturns: Set.of(_current.fxReturns)..remove(rtn),
        );
      });
      return;
    }

    int conflictIdx = -1;
    for (int i = 0; i < _configs.length; i++) {
      if (i != widget.groupIndex && _configs[i].fxReturns.contains(rtn)) {
        conflictIdx = i;
        break;
      }
    }

    if (conflictIdx != -1) {
      final confirmed = await _showReassignDialog(_fxReturnLabel(rtn), conflictIdx);
      if (confirmed != true) return;
      setState(() {
        _configs[conflictIdx] = _configs[conflictIdx].copyWith(
          fxReturns: Set.of(_configs[conflictIdx].fxReturns)..remove(rtn),
        );
        _configs[widget.groupIndex] = _current.copyWith(
          fxReturns: Set.of(_current.fxReturns)..add(rtn),
        );
      });
    } else {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(
          fxReturns: Set.of(_current.fxReturns)..add(rtn),
        );
      });
    }
  }

  Future<void> _toggleLineIn() async {
    if (_current.lineIn) {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(lineIn: false);
      });
      return;
    }

    int conflictIdx = -1;
    for (int i = 0; i < _configs.length; i++) {
      if (i != widget.groupIndex && _configs[i].lineIn) {
        conflictIdx = i;
        break;
      }
    }

    if (conflictIdx != -1) {
      final confirmed = await _showReassignDialog('LINE IN', conflictIdx);
      if (confirmed != true) return;
      setState(() {
        _configs[conflictIdx] = _configs[conflictIdx].copyWith(lineIn: false);
        _configs[widget.groupIndex] = _current.copyWith(lineIn: true);
      });
    } else {
      setState(() {
        _configs[widget.groupIndex] = _current.copyWith(lineIn: true);
      });
    }
  }

  Future<bool?> _showReassignDialog(String label, int conflictIdx) {
    final l = AppLocalizations.of(context)!;
    final otherName = _configs[conflictIdx].name;
    return showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l.channelAlreadyAssigned),
        content: Text(l.reassignConfirm(label, otherName, _current.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(
              l.reassign,
              style: const TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _configs);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_current.name),
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _configs),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l.renameGroup,
              onPressed: _renameGroup,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: MediaQuery.viewPaddingOf(context).left,
            right: MediaQuery.viewPaddingOf(context).right,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Channels 1-16 + Line In ─────────────────────────────────
              _SectionHeader(title: l.groupChannels),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...List.generate(16, (i) {
                      final ch = i + 1;
                      final selected = _current.channels.contains(ch);
                      String? otherGroup;
                      for (int j = 0; j < _configs.length; j++) {
                        if (j != widget.groupIndex && _configs[j].channels.contains(ch)) {
                          otherGroup = _configs[j].name;
                          break;
                        }
                      }
                      return FilterChip(
                        label: Text(_channelLabel(ch)),
                        selected: selected,
                        onSelected: (_) => _toggleChannel(ch),
                        labelStyle: !selected && otherGroup != null
                            ? const TextStyle(color: Colors.orange)
                            : null,
                        side: !selected && otherGroup != null
                            ? BorderSide(color: Colors.orange.withValues(alpha: 0.6))
                            : null,
                        tooltip: otherGroup != null ? l.inGroup(otherGroup) : null,
                      );
                    }),
                    Builder(builder: (context) {
                      final selected = _current.lineIn;
                      String? otherGroup;
                      for (int j = 0; j < _configs.length; j++) {
                        if (j != widget.groupIndex && _configs[j].lineIn) {
                          otherGroup = _configs[j].name;
                          break;
                        }
                      }
                      return FilterChip(
                        label: const Text('LINE'),
                        selected: selected,
                        onSelected: (_) => _toggleLineIn(),
                        labelStyle: !selected && otherGroup != null
                            ? const TextStyle(color: Colors.orange)
                            : null,
                        side: !selected && otherGroup != null
                            ? BorderSide(color: Colors.orange.withValues(alpha: 0.6))
                            : null,
                        tooltip: otherGroup != null ? l.inGroup(otherGroup) : null,
                      );
                    }),
                  ],
                ),
              ),

              // ── FX Returns 1-4 ──────────────────────────────────────────
              _SectionHeader(title: l.fxReturns),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(4, (i) {
                    final rtn = i + 1;
                    final selected = _current.fxReturns.contains(rtn);
                    String? otherGroup;
                    for (int j = 0; j < _configs.length; j++) {
                      if (j != widget.groupIndex && _configs[j].fxReturns.contains(rtn)) {
                        otherGroup = _configs[j].name;
                        break;
                      }
                    }
                    return FilterChip(
                      label: Text(_fxReturnLabel(rtn)),
                      selected: selected,
                      onSelected: (_) => _toggleFxReturn(rtn),
                      labelStyle: !selected && otherGroup != null
                          ? const TextStyle(color: Colors.orange)
                          : null,
                      side: !selected && otherGroup != null
                          ? BorderSide(color: Colors.orange.withValues(alpha: 0.6))
                          : null,
                      tooltip: otherGroup != null ? l.inGroup(otherGroup) : null,
                    );
                  }),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Text(
                  l.orangeInputsNote,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _GroupNameDialog extends StatefulWidget {
  final String defaultName;
  const _GroupNameDialog({required this.defaultName});

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
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
              Text(l.groupNameTitle, style: Theme.of(context).textTheme.titleLarge),
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
