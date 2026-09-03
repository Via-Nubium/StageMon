/// A group's members — channels, FX returns and the LINE input — flattened
/// into one list of int keys, so everything that walks a group (the group
/// fader's min/max, its subscriptions, the detail screen's columns) can hold
/// a single list instead of three.
///
/// The encoding: 1-16 is a channel, 101-104 an FX return, 200 the LINE input.
library;

import 'osc_addresses.dart';

/// The LINE input's key. FX return n is [kFxReturnBase] + n.
const int kLineInMember = 200;
const int kFxReturnBase = 100;

int fxReturnMember(int rtn) => kFxReturnBase + rtn;

bool isChannelMember(int member) => member <= 16;
bool isFxReturnMember(int member) => member > 16 && member < kLineInMember;
bool isLineInMember(int member) => member == kLineInMember;

/// The FX return number behind an FX return key.
int fxReturnOf(int member) => member - kFxReturnBase;

/// The members of a group, ordered the way the fader strip shows them:
/// channels first (sorted), then LINE, then the FX returns (sorted).
///
/// Callers that only aggregate — GroupFader's min/max and its subscription
/// set — don't care about the order; the detail screen's columns do, which is
/// why the order is fixed here rather than left to each caller.
List<int> groupMembers({
  required Iterable<int> channels,
  required Iterable<int> fxReturns,
  required bool lineIn,
}) {
  final sortedChannels = channels.toList()..sort();
  final sortedFxReturns = fxReturns.map(fxReturnMember).toList()..sort();
  return [...sortedChannels, if (lineIn) kLineInMember, ...sortedFxReturns];
}

/// The level address of one member in [bus]'s mix.
String memberLevelAddress(int member, int bus) {
  if (isChannelMember(member)) return channelLevelAddress(member, bus);
  if (isLineInMember(member)) return lineInLevelAddress(bus);
  return fxReturnLevelAddress(fxReturnOf(member), bus);
}

/// The pan address of one member in [bus]'s mix.
String memberPanAddress(int member, int bus) {
  if (isChannelMember(member)) return channelPanAddress(member, bus);
  if (isLineInMember(member)) return lineInPanAddress(bus);
  return fxReturnPanAddress(fxReturnOf(member), bus);
}
