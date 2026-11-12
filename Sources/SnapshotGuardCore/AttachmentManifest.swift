import Foundation

/// One test's attachments, as written to `manifest.json` by
/// `xcrun xcresulttool export attachments`.
public struct ManifestEntry: Decodable, Equatable, Sendable {
  public struct Attachment: Decodable, Equatable, Sendable {
    /// The file name inside the export directory.
    public var exportedFileName: String
    /// The name the test gave the attachment, followed by a counter and a UUID.
    public var suggestedHumanReadableName: String?
    /// Which attempt produced the attachment when the test was retried. Starts at 1.
    public var repetitionNumber: Int?

    public init(
      exportedFileName: String,
      suggestedHumanReadableName: String? = nil,
      repetitionNumber: Int? = nil
    ) {
      self.exportedFileName = exportedFileName
      self.suggestedHumanReadableName = suggestedHumanReadableName
      self.repetitionNumber = repetitionNumber
    }
  }

  /// The test identifier, such as `ScreenSnapshotTests/profile()`.
  public var testIdentifier: String
  public var attachments: [Attachment]

  public init(testIdentifier: String, attachments: [Attachment]) {
    self.testIdentifier = testIdentifier
    self.attachments = attachments
  }

  private enum CodingKeys: String, CodingKey {
    case testIdentifier, attachments
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    testIdentifier = try container.decode(String.self, forKey: .testIdentifier)
    attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
  }
}
