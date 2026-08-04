import Foundation

// OpenSSH invokes this helper with its prompt. The main app writes a
// session-only, mode-0600 credential map from passwords entered in its UI.
let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
let promptAccount = prompt.range(of: #"[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+"#, options: .regularExpression).map { String(prompt[$0]) }
guard let credentialPath = ProcessInfo.processInfo.environment["CAMERA_STREAM_CREDENTIALS_FILE"],
      let data = try? Data(contentsOf: URL(fileURLWithPath: credentialPath)),
      let credentials = try? JSONDecoder().decode([String: String].self, from: data),
      let account = promptAccount ?? ProcessInfo.processInfo.environment["CAMERA_STREAM_KEYCHAIN_ACCOUNT"],
      let password = credentials[account] else {
    exit(1)
}
FileHandle.standardOutput.write(Data(password.utf8))
FileHandle.standardOutput.write(Data("\n".utf8))
