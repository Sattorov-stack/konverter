import Foundation

/// Если среди файлов есть папки, достаёт из них все файлы (включая вложенные папки)
enum Expand {
    static func files(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                if let e = fm.enumerator(at: u, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let f as URL in e {
                        if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                            result.append(f)
                        }
                    }
                }
            } else {
                result.append(u)
            }
        }
        return result
    }
}
