import 'package:core/core.dart';

/// What the search hands to the add flow, as the `extra` of `addLocation`.
final class AddRequest {
  const AddRequest(this.candidate, {this.artworkInstanceId});

  /// The search result. `existingRefs` names the instances known to have it,
  /// `sourceByInstance` holds the record of each instance whose search found
  /// it; a target that is not among those has to look it up itself.
  final AddCandidate candidate;

  /// The instance whose artwork loader reads `candidate.images`: a path among
  /// them is under that instance's address. Null when the caller did not say.
  final String? artworkInstanceId;
}
