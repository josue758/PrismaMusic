import Foundation
import Darwin
import Synchronization

struct ScannedAudioFile: Sendable {
    var url:URL
    var modified:Date?
    var sidecarsKnown=false
    var coverURL:URL?
    var lyricsURL:URL?
    var sourceIsNetwork:Bool?
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
    /// Use directory entries rather than NSURL's bulk attribute prefetch, which can be very slow on SMB.
    static func enumerate(_ source:URL,recursive:Bool,cancellation:ScanCancellation = .init(),readModificationDates:Bool = true,progress:(@Sendable (Int)->Void)? = nil) -> SourceScanReport {
        var report=SourceScanReport(source:source,identity:nil,files:[],complete:true,errors:[])
        var lastProgress=Date()
        progress?(0); defer { progress?(report.files.count) }
        func record(_ url:URL,_ code:Int32) {
            report.complete=false
            if report.errors.count < 8 { report.errors.append(NSError(domain:NSPOSIXErrorDomain,code:Int(code),userInfo:[NSFilePathErrorKey:url.path]).localizedDescription) }
        }
        func info(_ url:URL) -> stat? {
            var value=stat()
            let result=url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.lstat($0,&value) } ?? -1 }
            guard result == 0 else { record(url,errno); return nil }; return value
        }
        func modified(_ value:stat) -> Date { Date(timeIntervalSince1970:Double(value.st_mtimespec.tv_sec)+Double(value.st_mtimespec.tv_nsec)/1_000_000_000) }
        guard !cancellation.isCancelled else { report.complete=false; return report }
        guard let root=info(source) else { return report }
        let network=(try? source.resourceValues(forKeys:[.volumeIsLocalKey]).volumeIsLocal).map { !$0 }
        report.identity=SourceIdentity(device:root.st_dev,inode:root.st_ino)
        let rootType=root.st_mode & S_IFMT
        if rootType == S_IFREG {
            if MetadataReader.extensions.contains(source.pathExtension.lowercased()) { report.files.append(.init(url:source,modified:modified(root),sourceIsNetwork:network)) }
            else { record(source,EINVAL) }
            return report
        }
        guard rootType == S_IFDIR else { record(source,EINVAL); return report }
        let packages:Set<String>=["app","bundle","framework","plugin","pkg","xcodeproj","xcworkspace","photoslibrary","musiclibrary"]
        var pending=[source]
        while let folder=pending.popLast() {
            if cancellation.isCancelled { report.complete=false; break }
            guard let directory=folder.withUnsafeFileSystemRepresentation({ path in path.flatMap { opendir($0) } }) else { record(folder,errno); continue }
            var audio:[ScannedAudioFile]=[]
            var images:[String:URL]=[:]; var lyrics:[String:URL]=[:]
            // Each directory handle is closed before moving to the next folder.
            do {
                defer { closedir(directory) }
                while !cancellation.isCancelled {
                    errno=0
                    guard let entry=readdir(directory) else { if errno != 0 { record(folder,errno) }; break }
                    let length=Int(entry.pointee.d_namlen)+1
                    guard let name=withUnsafePointer(to:&entry.pointee.d_name,{ pointer in
                        pointer.withMemoryRebound(to:CChar.self,capacity:length) { String(validatingCString:$0) }
                    }) else { record(folder,EILSEQ); continue }
                    if name.hasPrefix(".") { continue }
                    var kind=Int32(entry.pointee.d_type)
                    let url=folder.appendingPathComponent(name,isDirectory:kind == DT_DIR)
                    var attributes:stat?
                    if kind == DT_UNKNOWN {
                        attributes=info(url)
                        guard let attributes else { continue }
                        let type=attributes.st_mode & S_IFMT
                        kind=type == S_IFDIR ? DT_DIR : type == S_IFREG ? DT_REG : DT_LNK
                    }
                    if kind == DT_DIR {
                        if recursive && !packages.contains(url.pathExtension.lowercased()) { pending.append(url) }
                    } else if kind == DT_REG && MetadataReader.extensions.contains(url.pathExtension.lowercased()) {
                        let value=readModificationDates ? (attributes ?? info(url)) : nil
                        // Retain a discovered path even if stat fails; an incomplete read must never prune it.
                        audio.append(.init(url:url,modified:value.map(modified)))
                    } else if kind == DT_REG {
                        if ["cover.jpg","folder.jpg","cover.png"].contains(name.lowercased()) { images[name.lowercased()]=url }
                        else if ["lrc","txt"].contains(url.pathExtension.lowercased()) { lyrics[name.lowercased()]=url }
                    }
                    if Date().timeIntervalSince(lastProgress) >= 0.5 { progress?(report.files.count+audio.count); lastProgress=Date() }
                }
            }
            let cover=["cover.jpg","folder.jpg","cover.png","Folder.jpg"].compactMap { images[$0] }.first
            for index in audio.indices {
                audio[index].sourceIsNetwork=network; audio[index].sidecarsKnown=true; audio[index].coverURL=cover
                let base=audio[index].url.deletingPathExtension().lastPathComponent.lowercased()
                audio[index].lyricsURL=lyrics[base+".lrc"] ?? lyrics[base+".txt"]
            }
            report.files.append(contentsOf:audio)
        }
        if cancellation.isCancelled || SourceIdentity.read(source) != report.identity { report.complete=false }
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
