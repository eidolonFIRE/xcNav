enum ErrorCode {
  success,
  unknownError,
  invalidId, // invalid "pilot_id" or "group_id"
  invalidSecretId,
  deniedGroupAccess, // IE. making requests for a group you aren't in
  missingData, // essential message data was left null
  noop, // No change / Nothing to do (example: leaving group when you aren't in a group)
  // ... add more as needed
}
