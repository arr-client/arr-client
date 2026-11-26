/// Why a change to profiles or instances was refused.
enum RuleViolation {
  /// A name does not have 1 to 40 characters.
  nameLength,

  /// Another profile, or another instance of the profile, has the name.
  nameTaken,

  /// The only profile cannot be deleted.
  lastProfile,

  /// No registered module has the service type.
  unknownServiceType,

  /// The service of an instance cannot change.
  serviceTypeChanged,

  /// Not an http or https address, or one with user information, a query or a
  /// fragment.
  url,

  /// The custom certificate authority is larger than 64 KiB.
  customCaTooLarge,

  /// A custom header's name is not an HTTP token, or is reserved.
  headerName,

  /// Basic authentication and the service's API key need the same header.
  basicAuthWithApiKey,

  /// A link the instance may not have.
  link,
}
