import Foundation

/// One demo file written to disk by ``DemoInstaller``.
public struct InstalledDemo: Sendable, Equatable {
    public let name: String
    public let path: String
    public let executable: Bool

    public init(name: String, path: String, executable: Bool) {
        self.name = name
        self.path = path
        self.executable = executable
    }
}

public enum DemoInstallError: Error, Equatable, CustomStringConvertible {
    case corruptEmbeddedData(String)

    public var description: String {
        switch self {
        case .corruptEmbeddedData(let name):
            return "embedded demo '\(name)' could not be decoded (corrupt build)"
        }
    }
}

/// Writes the demos embedded in the binary (see ``embeddedDemos``) out to a
/// directory. Because the demos travel inside the executable, this behaves
/// identically no matter how apfel-plus was installed - homebrew-core, the
/// tariqwest tap, or a source build - which is the whole point: there is no
/// brew `--with-demo` option that could work the same on every channel.
public enum DemoInstaller {

    /// The demos baked into this build.
    public static var demos: [EmbeddedDemo] { embeddedDemos }

    /// Decode a single embedded demo's bytes.
    public static func decoded(_ demo: EmbeddedDemo) throws -> Data {
        guard let data = Data(base64Encoded: demo.base64) else {
            throw DemoInstallError.corruptEmbeddedData(demo.name)
        }
        return data
    }

    /// Write every embedded demo into `directory` (created if needed).
    ///
    /// - Parameters:
    ///   - directory: destination directory.
    ///   - overwrite: when false, existing files are left untouched and skipped.
    /// - Returns: the demos actually written, in embed order.
    @discardableResult
    public static func install(into directory: URL, overwrite: Bool = true) throws -> [InstalledDemo] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        var installed: [InstalledDemo] = []
        for demo in embeddedDemos {
            let dest = directory.appendingPathComponent(demo.name)
            if fm.fileExists(atPath: dest.path) && !overwrite {
                continue
            }
            let data = try decoded(demo)
            try data.write(to: dest, options: .atomic)
            if demo.isExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            }
            installed.append(
                InstalledDemo(name: demo.name, path: dest.path, executable: demo.isExecutable)
            )
        }
        return installed
    }
}
