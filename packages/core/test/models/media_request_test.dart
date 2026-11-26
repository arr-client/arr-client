// Whom deleting a request is offered to.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

MediaRequest _request(RequestStatus status) => MediaRequest(
  id: 1,
  titleRef: const DiscoveryRef(mediaType: DiscoveryMediaType.movie, tmdbId: 19),
  requestedBy: const ServiceUser(id: 2, name: 'Asker'),
  status: status,
  availability: Availability.unknown,
  is4k: false,
);

SessionUser _user(int id, [Set<ServicePermission> permissions = const {}]) =>
    SessionUser(id: id, name: 'User', permissions: permissions);

void main() {
  test('who manages requests may delete any', () {
    final manager = _user(1, {ServicePermission.manageRequests});

    for (final status in RequestStatus.values) {
      expect(_request(status).canBeDeletedBy(manager), isTrue);
    }
  });

  test('others only their own while it is pending', () {
    for (final status in RequestStatus.values) {
      expect(
        _request(status).canBeDeletedBy(_user(2)),
        status == RequestStatus.pending,
        reason: status.name,
      );
      expect(_request(status).canBeDeletedBy(_user(3)), isFalse);
    }
  });
}
