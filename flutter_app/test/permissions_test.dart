import 'package:flutter_test/flutter_test.dart';
import 'package:uber_maids_watch/core/models.dart';
import 'package:uber_maids_watch/core/permissions.dart';

AppUser user(String role, {Map<String, dynamic> capabilities = const {}}) {
  return AppUser(
    id: 'u1',
    username: role.toLowerCase(),
    displayName: role,
    role: role,
    capabilities: capabilities,
  );
}

void main() {
  group('Permissions', () {
    test('falls back to the role matrix when capabilities are absent', () {
      expect(Permissions.canWrite(user('ADMIN'), 'services'), isTrue);
      expect(Permissions.canWrite(user('OPERATIONS'), 'workers'), isTrue);
      expect(Permissions.canWrite(user('FINANCE'), 'payments'), isTrue);
      expect(Permissions.canWrite(user('FINANCE'), 'workers'), isFalse);
      expect(Permissions.canWrite(user('READONLY'), 'bookings'), isFalse);
      expect(Permissions.canWrite(null, 'workers'), isFalse);
    });

    test('prefers server capabilities when present', () {
      final capabilities = {
        'can_write': {'workers': false, 'payments': true},
      };
      expect(
        Permissions.canWrite(user('ADMIN', capabilities: capabilities), 'workers'),
        isFalse,
      );
      expect(
        Permissions.canWrite(user('ADMIN', capabilities: capabilities), 'payments'),
        isTrue,
      );
    });

    test('delete is stricter than write', () {
      expect(Permissions.canDelete(user('ADMIN'), 'workers'), isTrue);
      expect(Permissions.canDelete(user('OPERATIONS'), 'clients'), isFalse);
      expect(Permissions.canDelete(user('FINANCE'), 'payments'), isFalse);
    });

    test('navigation matches the role', () {
      expect(
        Permissions.sectionsFor(user('MAID')),
        containsAll(<String>['dashboard', 'workers', 'placements']),
      );
      expect(
        Permissions.sectionsFor(user('FAMILY')),
        containsAll(<String>['bookings', 'replacements', 'payments']),
      );
      expect(
        Permissions.sectionsFor(user('ADMIN')),
        contains('administration'),
      );
      expect(
        Permissions.sectionsFor(user('OPERATIONS')),
        isNot(contains('administration')),
      );
    });

    test('labels unknown roles gracefully', () {
      expect(Permissions.roleLabel('ADMIN'), 'Administrator');
      expect(Permissions.roleLabel('WHATEVER'), 'WHATEVER');
      expect(Permissions.sectionLabel('followups'), 'Follow-ups');
    });
  });
}
