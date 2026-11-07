import Foundation
import Darwin
import Synchronization

struct ScannedAudioFile: Sendable {
    var url:URL
    var modified:Date?
}
struct SourceIdentity: Equatable, Sendable {
    var device:Int32
    var inode:UInt64
    static func read(_ url:URL) -> Self? {
        var info=stat()
        guard url.withUnsafeFileSystemRepresentation({ path in path.map { Darwin.lstat($0,&info) } ?? -1 }) == 0 else { return nil }
        return .init(device:info.st_dev,inode:info.st_ino)
    }
}
struct SourceScanReport: Sendable {
    var source:URL
    var identity:SourceIdentity?
    var files:[ScannedAudioFile]
    var complete:Bool
    var errors:[String]
}
final class ScanCancellation: @unchecked Sendable {
    private let value=Atomic<Bool>(false)
    var isCancelled:Bool { value.load(ordering:.relaxed) }
    func cancel() { value.store(true,ordering:.relaxed) }
}
enum SourceScanner {
    static func enumerate(_ source:URL,recursive:Bool,cancellation:ScanCancellation = .init(),progress:(@Sendable (Int)->Void)? = nil) -> SourceScanReport {
        progress?(0)
        var lastProgress=Date()
        var report=SourceScanReport(source:source,identity:SourceIdentity.read(source),files:[],complete:true,errors:[])
        defer { progress?(report.files.count) }
        func record(_ error:Error) { report.complete=false; if report.errors.count < 8 { report.errors.append(error.localizedDescription) } }
        do {
            let root=try source.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.contentModificationDateKey])
            guard FileManager.default.isReadableFile(atPath:source.path) else { throw CocoaError(.fileReadNoPermission) }
            if root.isRegularFile == true {
                guard MetadataReader.extensions.contains(source.pathExtension.lowercased()) else { throw CocoaError(.fileReadUnsupportedScheme) }
                report.files=[.init(url:source,modified:root.contentModificationDate)]; return report
            }
            guard root.isDirectory == true else { throw CocoaError(.fileReadUnknown) }
            // Force a real directory read: a reachable path alone does not prove access to its contents.
            // Only the top level is held here; release it before the recursive enumeration starts.
            _ = try FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:[],options:[.skipsHiddenFiles])
            let options:FileManager.DirectoryEnumerationOptions=recursive ? [.skipsHiddenFiles,.skipsPackageDescendants] : [.skipsHiddenFiles,.skipsPackageDescendants,.skipsSubdirectoryDescendants]
            guard let enumerator=FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey],options:options,errorHandler:{ _,error in record(error); return !cancellation.isCancelled }) else { throw CocoaError(.fileReadUnknown) }
            while let url=enumerator.nextObject() as? URL {
                if cancellation.isCancelled { report.complete=false; break }
                if Date().timeIntervalSince(lastProgress) >= 0.5 { progress?(report.files.count); lastProgress=Date() }
                do {
                    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey])
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if values.isRegularFile == true && MetadataReader.extensions.contains(url.pathExtension.lowercased()) { report.files.append(.init(url:url,modified:values.contentModificationDate)) }
                } catch { record(error) }
            }
            if cancellation.isCancelled || SourceIdentity.read(source) != report.identity { report.complete=false }
        } catch { record(error) }
        return report
    }
    static func canReconcile(_ report:SourceScanReport,cancelled:Bool) -> Bool {
        guard report.complete, !cancelled, report.identity != nil, SourceIdentity.read(report.source) == report.identity, FileManager.default.isReadableFile(atPath:report.source.path) else { return false }
        // A final read catches a disconnect or access change after the initial enumeration.
        do {
            let values=try report.source.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey])
            if values.isDirectory == true { _ = try FileManager.default.contentsOfDirectory(at:report.source,includingPropertiesForKeys:[],options:[.skipsHiddenFiles]) }
            return true
        } catch { return false }
    }
    static func isWithin(_ file:URL,source:URL,recursive:Bool = true) -> Bool {
        if file.standardizedFileURL == source.standardizedFileURL { return true }
        if !recursive { return file.deletingLastPathComponent().standardizedFileURL == source.standardizedFileURL }
        let prefix=source.path.hasSuffix("/") ? source.path : source.path+"/"
        return file.path.hasPrefix(prefix)
    }
}
