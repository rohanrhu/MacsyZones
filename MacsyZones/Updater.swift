//
// MacsyZones, macOS system utility for managing windows on your Mac.
//
// https://macsyzones.com
//
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
//
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import AppKit
import Foundation
import Security

private let expectedUpdaterBundleIdentifier = "MeowingCat.MacsyZones"
private let expectedUpdaterTeamIdentifier = "59CP56H446"

struct GitHubRelease {
    let version: String
    let releaseURL: URL
    let downloadURL: URL?
}

class AppUpdater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdatable: Bool?
    @Published var isDownloading = false
    
    @Published var latestVersion: String?
    @Published var latestReleaseURL: URL?
    @Published var updateErrorMessage: String?
    
    let updater = GitHubUpdater()
    
    func checkForUpdates(download: Bool = false) {
        Task { @MainActor in
            self.isChecking = true
            self.updateErrorMessage = nil
        }
        
        updater.checkForUpdates(download: download) { release in
            guard let release = release else {
                Task { @MainActor in
                    self.isChecking = false
                    self.isDownloading = false
                    self.latestVersion = nil
                    self.latestReleaseURL = nil
                    self.isUpdatable = false
                }
                
                return
            }
            
            Task { @MainActor in
                self.latestVersion = release.version
                self.latestReleaseURL = release.releaseURL
                self.isChecking = false
                self.isUpdatable = true
                self.isDownloading = download
            }
        } onDownloaded: { success in
            Task { @MainActor in
                self.isChecking = false
                self.isDownloading = false

                if !success {
                    self.updateErrorMessage = "Update install failed. Open the release manually."
                }
            }
        }
    }
}

func isVersionGreater(_ version: String, than otherVersion: String) -> Bool {
    let cleanVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
    let cleanOtherVersion = otherVersion.hasPrefix("v") ? String(otherVersion.dropFirst()) : otherVersion
    
    let versionComponents = cleanVersion.split(separator: ".")
    let otherVersionComponents = cleanOtherVersion.split(separator: ".")
    
    let minComponents = min(versionComponents.count, otherVersionComponents.count)
    
    for i in 0..<minComponents {
        guard let vNum = Int(versionComponents[i]), let otherNum = Int(otherVersionComponents[i]) else {
            if versionComponents[i] > otherVersionComponents[i] {
                return true
            } else if versionComponents[i] < otherVersionComponents[i] {
                return false
            }
            continue
        }
        
        if vNum > otherNum {
            return true
        } else if vNum < otherNum {
            return false
        }
    }
    
    return versionComponents.count > otherVersionComponents.count
}

func getApplicationsPath() -> URL {
    return Bundle.main.bundleURL.deletingLastPathComponent()
}

class GitHubAPI {
    let session = URLSession.shared

    func checkLatestRelease(onChecked: @escaping (GitHubRelease?) -> Void) {
        let urlString = "https://api.github.com/repos/rohanrhu/MacsyZones/releases/latest"
        guard let url = URL(string: urlString) else {
            onChecked(nil)
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                onChecked(nil)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let releaseURLString = json["html_url"] as? String
                {
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                    let isGreater = isVersionGreater(version, than: appVersion)
                    let downloadURLString = ((json["assets"] as? [[String: Any]])?.first?["browser_download_url"] as? String)

                    guard isGreater, let releaseURL = URL(string: releaseURLString) else {
                        onChecked(nil)
                        return
                    }

                    onChecked(GitHubRelease(
                        version: version,
                        releaseURL: releaseURL,
                        downloadURL: downloadURLString.flatMap(URL.init(string:))
                    ))
                } else {
                    onChecked(nil)
                }
            } catch {
                debugLog("Error parsing JSON:")
                dump(error)
                onChecked(nil)
            }
        }
        
        task.resume()
    }
}

class GitHubUpdater {
    let githubAPI = GitHubAPI()
    let fileManager = FileManager.default
    let applicationsDirectory = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true).first!
    let appName = "MacsyZones"
    
    func checkForUpdates(download: Bool = false, onChecked: ((GitHubRelease?) -> Void)? = nil, onDownloaded: ((Bool) -> Void)? = nil) {
        githubAPI.checkLatestRelease { [self] latestRelease in
            guard let latestRelease else {
                onChecked?(nil)
                return
            }

            onChecked?(latestRelease)

            guard download else {
                return
            }

            guard let downloadURL = latestRelease.downloadURL else {
                debugLog("Error: Latest release does not include a downloadable app asset.")
                onDownloaded?(false)
                return
            }
            
            self.downloadZip(from: downloadURL, version: latestRelease.version) { success in
                onDownloaded?(success)
            }
        }
    }
    
    private func downloadZip(from url: URL, version: String, onCompleted: ((Bool) -> Void)? = nil) {
        let destination = URL(fileURLWithPath: "\(NSTemporaryDirectory())\(appName).zip")
        
        downloadFile(from: url, to: destination) { [self] tmpPath in
            guard let tmpPath = tmpPath else {
                debugLog("Error downloading update!")
                onCompleted?(false)
                return
            }
            
            let success = self.extractZip(from: tmpPath, version: version)
            onCompleted?(success)
        }
    }
    
    private func extractZip(from zipURL: URL, version: String) -> Bool {
        let fileManager = FileManager.default
        let destinationFolder = getApplicationsPath()
        let destinationApp = destinationFolder.appendingPathComponent("MacsyZones.app")
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            
            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            extractProcess.arguments = ["-xk", "--extattr", zipURL.path, tempDirectory.path]
            try extractProcess.run()
            extractProcess.waitUntilExit()
            
            let extractedAppURL = tempDirectory.appendingPathComponent("MacsyZones.app")
            guard fileManager.fileExists(atPath: extractedAppURL.path) else {
                debugLog("Error: Extracted app not found.")
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }
            
            let extractedInfoPlist = extractedAppURL.appendingPathComponent("Contents/Info.plist")
            guard let extractedPlistData = try? Data(contentsOf: extractedInfoPlist),
                  let extractedPlist = try? PropertyListSerialization.propertyList(from: extractedPlistData, options: [], format: nil) as? [String: Any],
                  let targetVersion = extractedPlist["CFBundleShortVersionString"] as? String else {
                debugLog("Error: Could not read target version from extracted app.")
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let targetBundleIdentifier = extractedPlist["CFBundleIdentifier"] as? String

            guard targetBundleIdentifier == expectedUpdaterBundleIdentifier else {
                debugLog("Error: Extracted app bundle identifier does not match MacsyZones.")
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }

            guard targetVersion == version else {
                debugLog("Error: Extracted app version does not match the GitHub release version.")
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }

            guard isVersionGreater(targetVersion, than: currentVersion) else {
                debugLog("Error: Extracted app is not newer than the current app.")
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }

            guard hasValidCodeSignature(at: extractedAppURL) else {
                try? fileManager.removeItem(at: tempDirectory)
                return false
            }

            updateState.setUpdateAttempt(currentVersion: currentVersion, targetVersion: targetVersion)
            
            let scriptURL = tempDirectory.appendingPathComponent("update.sh")
            let script = """
            #!/bin/bash
            sleep 2

            # Remove quarantine from extracted app (prevents GateKeeper issues)
            xattr -r -d com.apple.quarantine "\(extractedAppURL.path)" 2>/dev/null || true
            
            # Remove old app
            rm -rf "\(destinationApp.path)"
            
            # Use ditto to preserve extended attributes during move
            ditto "\(extractedAppURL.path)" "\(destinationApp.path)"

            # Final quarantine cleanup on installed app
            xattr -r -d com.apple.quarantine "\(destinationApp.path)" 2>/dev/null || true
            
            # Give filesystem time to settle
            sleep 1
            
            open "\(destinationApp.path)"
            rm -rf "\(tempDirectory.path)"
            exit 0
            """
            
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            let updateProcess = Process()
            updateProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            updateProcess.arguments = ["-c", "nohup \"\(scriptURL.path)\" > /dev/null 2>&1 &"]
            try updateProcess.run()
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.window.level = .floating
                alert.alertStyle = .informational
                alert.messageText = "MacsyZones"
                alert.informativeText = "An update will now start. The app will restart automatically."
                alert.addButton(withTitle: "OK")
                
                alert.window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                
                alert.runModal()
                
                restartApp()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }

            return true
        } catch {
            debugLog("Update error: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDirectory)
            return false
        }
    }

    private func hasValidCodeSignature(at appURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode)

        guard createStatus == errSecSuccess, let staticCode = staticCode else {
            debugLog("Error: Could not read update code signature. OSStatus: \(createStatus)")
            return false
        }

        let validationFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, nil)

        guard validationStatus == errSecSuccess else {
            debugLog("Error: Update code signature is invalid. OSStatus: \(validationStatus)")
            return false
        }

        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)

        guard infoStatus == errSecSuccess,
              let info = signingInfo as? [String: Any],
              let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String else {
            debugLog("Error: Could not read update signing team. OSStatus: \(infoStatus)")
            return false
        }

        guard teamIdentifier == expectedUpdaterTeamIdentifier else {
            debugLog("Error: Update signing team does not match MacsyZones.")
            return false
        }

        return true
    }
}

func downloadFile(from url: URL, to destination: URL, onComplete: @escaping (URL?) -> Void) {
    let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
        guard let tempURL = tempURL, error == nil else {
            onComplete(nil)
            return
        }
        
        onComplete(tempURL)
    }
    task.resume()
}
