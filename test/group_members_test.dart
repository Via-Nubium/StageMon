import 'package:flutter_test/flutter_test.dart';
import 'package:stagemon/utils/group_members.dart';
import 'package:stagemon/utils/osc_addresses.dart';

// The encoding that lets a group be walked as one list of int keys, which
// GroupFader and GroupDetailScreen used to spell out separately. The address
// strings themselves are pinned in osc_addresses_test.dart.

void main() {
  group('member encoding', () {
    test('separates the three kinds', () {
      expect(isChannelMember(1), isTrue);
      expect(isChannelMember(16), isTrue);
      expect(isFxReturnMember(16), isFalse);
      expect(isFxReturnMember(fxReturnMember(1)), isTrue);
      expect(isFxReturnMember(fxReturnMember(4)), isTrue);
      expect(isLineInMember(kLineInMember), isTrue);
      expect(isFxReturnMember(kLineInMember), isFalse);
      expect(isChannelMember(kLineInMember), isFalse);
    });

    test('round trips an FX return number', () {
      for (var rtn = 1; rtn <= 4; rtn++) {
        expect(fxReturnOf(fxReturnMember(rtn)), rtn);
      }
    });
  });

  group('groupMembers', () {
    test('orders channels, then LINE, then FX returns', () {
      expect(
        groupMembers(channels: {5, 1, 3}, fxReturns: {4, 2}, lineIn: true),
        [1, 3, 5, kLineInMember, fxReturnMember(2), fxReturnMember(4)],
      );
    });

    test('leaves out what the group does not include', () {
      expect(
        groupMembers(channels: {2}, fxReturns: const <int>{}, lineIn: false),
        [2],
      );
      expect(
        groupMembers(
          channels: const <int>{},
          fxReturns: const <int>{},
          lineIn: false,
        ),
        isEmpty,
      );
    });
  });

  group('member addresses', () {
    test('route each kind to its own address shape', () {
      expect(memberLevelAddress(3, 1), '/ch/03/mix/01/level');
      expect(memberPanAddress(3, 1), '/ch/03/mix/01/pan');
      expect(memberLevelAddress(fxReturnMember(2), 1), '/rtn/2/mix/01/level');
      expect(memberPanAddress(fxReturnMember(2), 1), '/rtn/2/mix/01/pan');
      expect(memberLevelAddress(kLineInMember, 1), '/rtn/aux/mix/01/level');
      expect(memberPanAddress(kLineInMember, 1), '/rtn/aux/mix/01/pan');
    });

    test('agree with the per-kind functions for every member of a group', () {
      final members = groupMembers(
        channels: {1, 16},
        fxReturns: {1, 4},
        lineIn: true,
      );
      expect(members.map((m) => memberLevelAddress(m, 6)), [
        channelLevelAddress(1, 6),
        channelLevelAddress(16, 6),
        lineInLevelAddress(6),
        fxReturnLevelAddress(1, 6),
        fxReturnLevelAddress(4, 6),
      ]);
    });
  });
}
