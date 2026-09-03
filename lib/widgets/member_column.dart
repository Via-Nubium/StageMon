import 'package:flutter/material.dart';

import '../controllers/fader_strip_controller.dart';
import '../controllers/mixer_controller.dart';
import '../models/mixer_layout_state.dart';
import '../utils/group_members.dart';
import 'custom_fader.dart';
import 'fader_column.dart';
import 'pan_knob.dart';

/// One strip column for a group member — a channel, an FX return or the LINE
/// input.
///
/// What differs between the three is a fact about the member (where its name,
/// meter and color come from, and the teal FX returns wear), not about the
/// screen drawing it. So the mixer's strip and a group's detail screen build
/// the same column from here, and a member looks and behaves the same in both.
class MemberColumn extends StatelessWidget {
  const MemberColumn({
    super.key,
    required this.member,
    required this.ctrl,
    required this.layout,
    required this.strip,
  });

  final int member;
  final MixerController ctrl;

  /// Only for the user's own color overrides; everything else comes from the
  /// console through [ctrl].
  final MixerLayoutState layout;
  final FaderStripController strip;

  String get _label {
    if (isChannelMember(member)) return ctrl.channelLabel(member);
    if (isFxReturnMember(member)) return ctrl.fxReturnLabel(fxReturnOf(member));
    return 'LINE';
  }

  /// The override the user picked in Settings, else the console's own
  /// scribble-strip color, else the neutral one.
  int get _nameColorIndex {
    if (isChannelMember(member)) {
      return layout.channelColors[member] ??
          ctrl.consoleChannelColors[member] ??
          0;
    }
    if (isFxReturnMember(member)) {
      final rtn = fxReturnOf(member);
      return layout.fxReturnColors[rtn] ?? ctrl.consoleFxReturnColors[rtn] ?? 0;
    }
    return layout.lineInColor ?? ctrl.consoleLineInColor ?? 0;
  }

  ValueNotifier<double> get _meterLevel {
    if (isChannelMember(member)) return ctrl.meterLevels[member - 1];
    if (isFxReturnMember(member)) {
      return ctrl.fxReturnMeterL[fxReturnOf(member) - 1];
    }
    return ctrl.lineInMeterL;
  }

  /// Null for channels: the console meters them mono, so there is no second
  /// bar to draw.
  ValueNotifier<double>? get _meterLevelRight {
    if (isChannelMember(member)) return null;
    if (isFxReturnMember(member)) {
      return ctrl.fxReturnMeterR[fxReturnOf(member) - 1];
    }
    return ctrl.lineInMeterR;
  }

  // Every column reserves the same height above its fader, so the faders line
  // up: a pan knob when the bus is a stereo pair, an empty gap when it isn't.
  Widget get _head {
    if (!ctrl.busPaired) return const SizedBox(height: kPanKnobHeight);
    return ForeignGestureArea(
      child: PanKnob(
        key: ValueKey('pan_$member'),
        oscAddress: memberPanAddress(member, ctrl.effectiveBus),
        service: ctrl.service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FaderColumn(
      width: strip.faderWidth,
      head: _head,
      child: CustomFader(
        key: ValueKey(member),
        label: _label,
        oscAddress: memberLevelAddress(member, ctrl.effectiveBus),
        service: ctrl.service,
        accentColor: isFxReturnMember(member)
            ? Colors.teal
            : CustomFader.defaultAccent,
        nameColorIndex: _nameColorIndex,
        meterLevel: _meterLevel,
        meterLevelRight: _meterLevelRight,
        controller: strip.controllerFor(member),
      ),
    );
  }
}
