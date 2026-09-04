import 'package:flutter/material.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import '../controllers/fader_strip_controller.dart';
import '../controllers/mixer_controller.dart';
import '../models/group_fader_config.dart';
import '../models/mixer_layout_state.dart';
import '../utils/group_members.dart';
import '../widgets/fader_strip.dart';
import '../widgets/member_column.dart';
import 'group_config_screen.dart';

/// The members of one group, each on its own fader — the same strip the mixer
/// screen shows, holding only what this group contains and no MASTER.
///
/// Its faders read live from [ctrl], so a name or color the console reports
/// while this screen is open lands here too. [layout] is only the user's own
/// color overrides, and is the snapshot taken when this screen was opened.
class GroupDetailScreen extends StatefulWidget {
  final int groupIndex;
  final MixerController ctrl;
  final MixerLayoutState layout;
  final void Function(List<GroupFaderConfig>) onConfigsChanged;

  const GroupDetailScreen({
    super.key,
    required this.groupIndex,
    required this.ctrl,
    required this.layout,
    required this.onConfigsChanged,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late List<GroupFaderConfig> _configs;

  // Its own strip, and its own remembered width: a group of three faders is
  // usually wanted spread across the screen even when the mixer is packed.
  final FaderStripController _strip = FaderStripController(
    widthPrefsKey: 'group_fader_width',
  );

  GroupFaderConfig get _config => _configs[widget.groupIndex];

  @override
  void initState() {
    super.initState();
    _configs = widget.layout.groups;
    _strip.addListener(_onStripChanged);
    _strip.loadSavedWidth();
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  void _onStripChanged() {
    if (mounted) setState(() {});
  }

  void _openConfig() async {
    final result = await Navigator.push<List<GroupFaderConfig>>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupConfigScreen(
          configs: _configs,
          groupIndex: widget.groupIndex,
          channelNames: widget.ctrl.channelNames,
          fxReturnNames: widget.ctrl.fxReturnNames,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _configs = result);
      widget.onConfigsChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final members = groupMembers(
          channels: _config.channels,
          fxReturns: _config.fxReturns,
          lineIn: _config.lineIn,
        );
        _strip.pruneControllers(members);
        return Scaffold(
          appBar: AppBar(
            title: Text(l.groupTitle(_config.name)),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: l.editGroupChannels,
                onPressed: _openConfig,
              ),
            ],
          ),
          body: members.isEmpty
              ? Center(child: Text(l.noChannelsInGroup))
              : Column(
                  children: [
                    Expanded(
                      child: FaderStrip(
                        controller: _strip,
                        padding: EdgeInsets.only(
                          left: MediaQuery.viewPaddingOf(context).left,
                          right: MediaQuery.viewPaddingOf(context).right,
                        ),
                        columns: [
                          for (final member in members)
                            MemberColumn(
                              key: ValueKey(member),
                              member: member,
                              ctrl: widget.ctrl,
                              layout: widget.layout,
                              strip: _strip,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: MediaQuery.viewPaddingOf(context).bottom),
                  ],
                ),
        );
      },
    );
  }
}
