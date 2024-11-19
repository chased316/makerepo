import Foundation
import CryptoKit

struct RepoInitializer {
    static let tokenFile = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.mr_token"
    
    static func getDeviceIdentifier() -> String {
        // Try to get persistent machine ID first
        if let id = try? String(contentsOf: URL(fileURLWithPath: "/etc/machine-id"), encoding: .utf8) {
            return id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // On macOS, get IOPlatformUUID which is persistent
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-d2", "-c", "IOPlatformExpertDevice"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if let range = output.range(of: "IOPlatformUUID\" = \"([^\"]+)\"", options: .regularExpression),
               let uuidRange = output[range].range(of: "\"([^\"]+)\"$", options: .regularExpression) {
                return String(output[uuidRange]).replacingOccurrences(of: "\"", with: "")
            }
        } catch {
            // If we can't get a persistent ID, we should fail rather than use a random one
            fatalError("Could not get persistent machine identifier")
        }
        
        // If we couldn't get a persistent ID, we should fail rather than risk inconsistent encryption
        fatalError("Could not get persistent machine identifier")
    }
    
    static func encryptToken(_ token: String) throws -> String {
        let deviceId = getDeviceIdentifier()
        let key = SymmetricKey(data: SHA256.hash(data: deviceId.data(using: .utf8)!))
        let tokenData = token.data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(tokenData, using: key)
        return sealedBox.combined!.base64EncodedString()
    }
    
    static func decryptToken(_ encrypted: String) throws -> String {
        let deviceId = getDeviceIdentifier()
        let key = SymmetricKey(data: SHA256.hash(data: deviceId.data(using: .utf8)!))
        let data = Data(base64Encoded: encrypted)!
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return String(data: decryptedData, encoding: .utf8)!
    }
    
    static func getStoredToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenFile),
              let encrypted = try? String(contentsOfFile: tokenFile, encoding: .utf8) else {
            return nil
        }
        
        return try decryptToken(encrypted)
    }
    
    static func validateToken(_ token: String) -> (isValid: Bool, message: String?) {
        // Check if token starts with expected prefix
        if !token.starts(with: "ghp_") {
            return (false, "Token must start with 'ghp_'")
        }
        
        // Check for valid characters (alphanumeric)
        if !token.dropFirst(4).allSatisfy({ $0.isLetter || $0.isNumber }) {
            return (false, "Token should only contain letters and numbers after 'ghp_'")
        }
        
        return (true, nil)
    }
    
    static func storeToken(_ token: String) throws {
        // Get the directory path
        let tokenDir = (tokenFile as NSString).deletingLastPathComponent
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: tokenDir) {
            try FileManager.default.createDirectory(
                atPath: tokenDir,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o700]
            )
        }
        
        // Encrypt and store token
        let encrypted = try encryptToken(token)
        try encrypted.write(toFile: tokenFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile)
    }
    
    static func promptForNewToken() throws -> String {
        var attempts = 0
        let maxAttempts = 3
        
        while attempts < maxAttempts {
            print("""
            🔑 GitHub Personal Access Token (PAT) required.
            
            To generate a new PAT:
            1. Visit: https://github.com/settings/tokens
            2. Click "Generate new token" (classic)
            3. Give it a name (e.g., "mr-tool")
            4. Select scopes: 'repo' and 'workflow'
            5. Click "Generate token"
            6. Copy the generated token and paste it below
            """)
            
            print("\nPAT: ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                attempts += 1
                print("\n❌ Token cannot be empty")
                continue
            }
            
            let validation = validateToken(input)
            if !validation.isValid {
                attempts += 1
                print("\n❌ Invalid token format: \(validation.message ?? "unknown error")")
                if attempts < maxAttempts {
                    print("Please try again (\(maxAttempts - attempts) attempts remaining)\n")
                }
                continue
            }
            
            try storeToken(input)
            return input
        }
        
        throw NSError(domain: "TokenError", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Maximum token entry attempts exceeded"
        ])
    }
    
    static func getToken() throws -> String {
        if let token = try getStoredToken() {
            return token
        }
        return try promptForNewToken()
    }
    
    static func isGitHubAuthenticated() -> Bool {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/gh"
        task.arguments = ["auth", "status"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func clearGitHubAuth() {
        // Attempt to logout, ignore any errors
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/gh"
        task.arguments = ["auth", "logout", "--hostname", "github.com"]
        try? task.run()
        task.waitUntilExit()
    }
    
    static func clearScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
    }
    
    static func run() {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: mr <repo-name>")
            exit(1)
        }
        
        let repoName = CommandLine.arguments[1]
        
        do {
            if !isGitHubAuthenticated() {
                clearGitHubAuth()
                let token = try getToken()
                
                // Instead of trying to login, just set the token in environment
                var environment = ProcessInfo.processInfo.environment
                environment["GH_TOKEN"] = token
                
                print("📦 Creating repository '\(repoName)' on GitHub...")
                let task = Process()
                task.environment = environment
                task.launchPath = "/opt/homebrew/bin/gh"
                task.arguments = [
                    "repo", "create", repoName,
                    "--private",
                    "--clone"
                ]
                
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    print("\n❌ Authentication failed: Invalid GitHub token")
                    try? FileManager.default.removeItem(atPath: tokenFile)
                    exit(1)
                }
            }
            
            FileManager.default.changeCurrentDirectoryPath(repoName)
            
            let readmeContent = "# \(repoName)\n\nProject repository created with mr"
            try readmeContent.write(
                toFile: "README.md",
                atomically: true,
                encoding: .utf8
            )
            
            print("📝 Creating initial commit...")
            try runCommand(command: "/usr/bin/git", arguments: ["add", "."])
            try runCommand(
                command: "/usr/bin/git",
                arguments: ["commit", "-m", "Initial commit"]
            )
            
            print("🚀 Pushing to GitHub...")
            try runCommand(command: "/usr/bin/git", arguments: ["push", "-u", "origin", "main"])
            
            print("✅ Successfully created repository '\(repoName)'!")
            print("   Local path: \(FileManager.default.currentDirectoryPath)")
            print("   GitHub URL: https://github.com/\(try getGitHubUser())/\(repoName)")
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    static func getGitHubUser() throws -> String {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/gh"
        task.arguments = ["api", "user", "--jq", ".login"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let username = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw NSError(domain: "GitHubError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not get GitHub username"
            ])
        }
        
        return username
    }
    
    static func runCommand(command: String, arguments: [String], input: String? = nil) throws {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe
        
        if let input = input {
            let inputPipe = Pipe()
            task.standardInput = inputPipe
            
            // Write the input with a newline and flush immediately
            let inputString = input + "\n"
            try inputPipe.fileHandleForWriting.write(contentsOf: inputString.data(using: .utf8)!)
            try inputPipe.fileHandleForWriting.synchronize()
            try inputPipe.fileHandleForWriting.close()
        }
        
        try task.run()
        task.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if task.terminationStatus != 0 {
            if let errorMessage = String(data: outputData, encoding: .utf8) {
                throw NSError(domain: "CommandError", code: Int(task.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            }
        }
        
        // Print output for debugging
        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print(output)
        }
    }
}

// Entry point
RepoInitializer.run()
