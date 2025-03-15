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

import Foundation

class AppUpdater: ObservableObject {
    @Published var isChecking = false
    @Published var isUpdatable: Bool?
    @Published var isDownloading = false
    
    @Published var latestVersion: String?
    
    let updater = GitHubUpdater()
    
    func checkForUpdates(download: Bool = false) {
        Task { @MainActor in
            self.isChecking = true
        }
        
        updater.checkForUpdates { version in
            guard let version = version else {
                Task { @MainActor in
                    self.isChecking = false
                    self.isDownloading = false
                    self.isUpdatable = false
                }
                
                return
            }
            
            Task { @MainActor in
                self.latestVersion = version
                self.isChecking = false
                self.isUpdatable = true
                self.isDownloading = true
            }
        } onDownloaded: { success in
            Task { @MainActor in
                self.isChecking = false
                self.isDownloading = false
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

    func checkLatestRelease(onChecked: @escaping ((version: String, url: URL)?) -> Void) {
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
                   let assets = json["assets"] as? [[String: Any]],
                   let downloadUrl = assets.first?["browser_download_url"] as? String
                {
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
                    let isGreater = true || isVersionGreater(version, than: appVersion)
                    
                    onChecked(isGreater ? (version: version, url: URL(string: downloadUrl)!): nil)
                } else {
                    onChecked(nil)
                }
            } catch {
                print("Error parsing JSON:")
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
    
    func checkForUpdates(onChecked: ((String?) -> Void)? = nil, onDownloaded: ((Bool) -> Void)? = nil) {
        githubAPI.checkLatestRelease { [self] latestRelease in
            guard let latestRelease else {
                onChecked?(nil)
                return
            }
            
            onChecked?(latestRelease.version)
            
            self.downloadZip(from: latestRelease.url, version: latestRelease.version) { success in
                onDownloaded?(success)
            }
        }
    }
    
    private func downloadZip(from url: URL, version: String, onCompleted: ((Bool) -> Void)? = nil) {
        let destination = URL(fileURLWithPath: "\(NSTemporaryDirectory())\(appName).zip")
        
        downloadFile(from: url, to: destination) { [self] tmpPath in
            guard let tmpPath = tmpPath else {
                print("Error downloading update!")
                onCompleted?(false)
                return
            }
            
            onCompleted?(true)
            
            self.extractZip(from: tmpPath)
        }
    }
    
    private func extractZip(from zipURL: URL) {
        let fileManager = FileManager.default
        let destinationFolder = getApplicationsPath()
        let destinationApp = destinationFolder.appendingPathComponent("MacsyZones.app")
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            
            let extractProcess = Process()
            extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            extractProcess.arguments = ["-xk", zipURL.path, tempDirectory.path]
            try extractProcess.run()
            extractProcess.waitUntilExit()
            
            let extractedAppURL = tempDirectory.appendingPathComponent("MacsyZones.app")
            guard fileManager.fileExists(atPath: extractedAppURL.path) else {
                print("Error: Extracted app not found.")
                try? fileManager.removeItem(at: tempDirectory)
                return
            }
            
            let scriptURL = tempDirectory.appendingPathComponent("update.sh")
            let script = """
            #!/bin/bash
            sleep 2
            rm -rf "\(destinationApp.path)"
            mv "\(extractedAppURL.path)" "\(destinationApp.path)"
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
                alert.alertStyle = .critical
                alert.messageText = "MacsyZones"
                alert.informativeText = "An update will now start. The app will restart automatically."
                alert.addButton(withTitle: "OK")
                
                alert.window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                
                alert.runModal()
                
                restartApp()
                
                NSApp.terminate(nil)
            }
        } catch {
            print("Update error: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDirectory)
        }
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
