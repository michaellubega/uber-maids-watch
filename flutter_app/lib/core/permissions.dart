import 'models.dart';

/// Client-side mirror of the server's role matrix.
///
/// This only decides which buttons and screens are shown.  The Django API
/// re-checks every permission, so hiding a control is a usability aid, not a
/// security boundary.
class Permissions {
  static const Map<String, Set<String>> _fallback = {
    'ADMIN': {
      'workers',
      'clients',
      'services',
      'bookings',
      'placements',
      'followups',
      'replacements',
      'payments',
    },
    'OPERATIONS': {
      'workers',
      'clients',
      'bookings',
      'placements',
      'followups',
      'replacements',
    },
    'VERIFICATION': {'workers'},
    'CUSTOMER_CARE': {'clients', 'bookings', 'followups', 'replacements'},
    'FINANCE': {'payments'},
    'READONLY': <String>{},
    'MAID': <String>{},
    'FAMILY': {'bookings', 'replacements'},
  };

  static bool canWrite(AppUser? user, String entity) {
    if (user == null) return false;
    final canWrite = user.capabilities['can_write'];
    if (canWrite is Map && canWrite[entity] is bool) {
      return canWrite[entity] as bool;
    }
    return (_fallback[user.role] ?? const <String>{}).contains(entity);
  }

  static bool canDelete(AppUser? user, String entity) {
    if (user == null) return false;
    if (user.role == 'ADMIN') return true;
    if (user.role == 'OPERATIONS') {
      return const {'bookings', 'followups', 'replacements'}.contains(entity);
    }
    return false;
  }

  static bool get isFamilyFallback => false;

  static bool isFamily(AppUser? user) => user?.role == 'FAMILY';

  static bool isMaid(AppUser? user) => user?.role == 'MAID';

  static bool seesAllStaff(AppUser? user) => user?.isStaff == true;

  static List<String> sectionsFor(AppUser? user) {
    if (user == null) return const <String>[];
    if (user.role == 'MAID') {
      return const ['dashboard', 'workers', 'placements', 'followups'];
    }
    if (user.role == 'FAMILY') {
      return const [
        'dashboard',
        'bookings',
        'placements',
        'followups',
        'replacements',
        'payments',
        'services',
      ];
    }
    final sections = <String>[
      'dashboard',
      'workers',
      'clients',
      'bookings',
      'placements',
      'followups',
      'replacements',
    ];
    if (const {'ADMIN', 'OPERATIONS', 'FINANCE', 'READONLY'}
        .contains(user.role)) {
      sections.add('payments');
    }
    sections.add('services');
    sections.add('sync');
    if (user.role == 'ADMIN') sections.add('administration');
    return sections;
  }

  static String roleLabel(String role) {
    switch (role) {
      case 'ADMIN':
        return 'Administrator';
      case 'OPERATIONS':
        return 'Operations manager';
      case 'VERIFICATION':
        return 'Verification officer';
      case 'CUSTOMER_CARE':
        return 'Customer care';
      case 'FINANCE':
        return 'Finance officer';
      case 'READONLY':
        return 'Read-only manager';
      case 'MAID':
        return 'Domestic worker';
      case 'FAMILY':
        return 'Client / family';
      default:
        return role;
    }
  }

  static String sectionLabel(String section) {
    switch (section) {
      case 'dashboard':
        return 'Dashboard';
      case 'workers':
        return 'Workers';
      case 'clients':
        return 'Clients';
      case 'bookings':
        return 'Bookings';
      case 'placements':
        return 'Placements';
      case 'followups':
        return 'Follow-ups';
      case 'replacements':
        return 'Replacements';
      case 'payments':
        return 'Payments';
      case 'services':
        return 'Services';
      case 'sync':
        return 'Offline & sync';
      case 'administration':
        return 'Administration';
      default:
        return section;
    }
  }
}
