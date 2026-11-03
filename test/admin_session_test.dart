import 'package:agritrade/screen/admin_notifications.dart';
import 'package:agritrade/services/audit_log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 11, 21);
  test('the session events are audit actions', () {
    expect(
      AuditAction.all,
      containsAll([
        AuditAction.newDeviceLogin,
        AuditAction.sessionReplaced,
        AuditAction.sessionForcedLogout,
      ]),
    );
  });

  test('a login is a notification; a session picked up again is not', () {
    final items = buildAdminNotifications(
      orders: const [],
      users: const [],
      reports: const [],
      announcements: const [],
      signIns: [
        (
          id: 'session-b',
          data: {
            'startedAt': Timestamp.fromDate(
              now.subtract(const Duration(minutes: 5)),
            ),
            'deviceName': 'Chrome on Windows',
            'newDevice': true,
          },
        ),
        (
          id: 'session-c',
          data: {
            'startedAt': Timestamp.fromDate(
              now.subtract(const Duration(minutes: 3)),
            ),
            'deviceName': 'Edge on Windows',
            'announced': false,
          },
        ),
      ],
      now: now,
    );
    expect(items, hasLength(1));
    expect(items.single.title, 'New Admin login detected');
    expect(items.single.detail, contains('new device'));
    expect(items.single.detail, contains('Chrome on Windows'));
    expect(items.single.target, AdminNotificationTarget.auditLog);
  });
}
