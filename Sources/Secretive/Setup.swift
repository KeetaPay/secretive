//
//  Setup.swift
//  Secretive
//
//  Created by David Scheutz on 9/20/22.
//  Copyright © 2022 Max Goedjen. All rights reserved.
//

import Foundation
import SecretKit

enum Command {
    case setGPGFormat
    case enableGPGSign
    case gitVersion
    case setSigningKey(key: String)
    
    var executable: String {
        switch self {
        case .setGPGFormat, .enableGPGSign, .gitVersion, .setSigningKey:
            return "/opt/homebrew/bin/git"
        }
    }
    
    var isAlias: Bool {
        switch self {
        case .setGPGFormat, .enableGPGSign, .gitVersion, .setSigningKey:
            return true
        }
    }
    
    var commands: [String] {
        switch self {
        case .setGPGFormat:
            return ["config", "--global", "gpg.format", "ssh"]
        case .enableGPGSign:
            return ["config", "--global", "commit.gpgsign", "true"]
        case .setSigningKey(let key):
            return ["config", "--global", "user.signingkey", key]
        case .gitVersion:
            return ["--version"]
        }
    }
}

private func execute(_ command: Command) async -> Bool {
    await withCheckedContinuation { continuation in
        let completion: (Bool) -> Void = { continuation.resume(with: .success($0)) }
        
        do {
            let executableURL: URL
            if command.isAlias {
                let url = URL(fileURLWithPath: command.executable)
                executableURL = try URL(resolvingAliasFileAt: url)
            } else {
                executableURL = URL(fileURLWithPath: command.executable)
            }
            
            guard FileManager.default.fileExists(atPath: executableURL.path) else {
                throw NSError(domain: "Executable doesn't exist.", code: 4)
            }
            
            try Process.run(executableURL, arguments: command.commands) { _ in
                completion(true)
            }
        } catch let error {
            print(error)
            completion(false)
        }
    }
}

@discardableResult
private func add(_ text: String, to fileURL: URL) -> Bool {
    let handle: FileHandle
    do {
        handle = try FileHandle(forUpdating: fileURL)
        
        let existing = try handle.readToEnd() ?? .init()
        let existingString = String(data: existing, encoding: .utf8) ?? ""
        
        guard !existingString.contains(text) else { return true }
        
        try handle.seekToEnd()
    } catch let error {
        print(error)
        return false
    }

    handle.write("\n# Secretive Keeta Config\n\(text)\n".data(using: .utf8)!)
    
    return true
}

let homeDirectory = NSHomeDirectory().replacingOccurrences(of: Bundle.main.hostBundleID, with: Bundle.main.agentBundleID)

func setupKeeta() async -> Bool {
    var success = true
    
    success = await execute(.setGPGFormat) && success
    success = await execute(.enableGPGSign) && success
    
    let appPath = homeDirectory as NSString
    let socketPath = appPath.appendingPathComponent("socket.ssh") as String
    
    // SSH_AUTH_SOCK
    success = success && add("export SSH_AUTH_SOCK=\(socketPath)", to: .init(fileURLWithPath: "\(appPath)/.zshrc"))
    
    // IdentityAgent
    success = success && add("Host *\n\tIdentityAgent \(socketPath)", to: .init(fileURLWithPath: "\(appPath)/.ssh/config"))
    
    return success
}

func updateSigningKey<T: Secret>(using secret: T) {
    let publicKeyFileStoreController = PublicKeyFileStoreController(homeDirectory: homeDirectory)
    let keyPath = publicKeyFileStoreController.path(for: secret)
    
    Task {
        await execute(.setSigningKey(key: keyPath))
    }
}
