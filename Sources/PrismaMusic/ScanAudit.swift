import Foundation
import Darwin

struct ScanIssue:Codable,Sendable {
    var url:URL
    var message:String
}
struct ScanAudit:Codable,Sendable {
    var startedAt=Date()
    var finishedAt:Date?
    var discovered=0
    var imported=0
    var unchanged=0
    var failed=0
    var unavailableSources=0
    var cancelled=false
    var issues:[ScanIssue]=[]
}
struct ScannedTrackResult:Sendable {
    var file:ScannedAudioFile
    var track:Track?
    var error:String?
    var unchanged=false
    static func read(_ file:ScannedAudioFile,cached:Track? = nil,force:Bool = false) async -> Self {
        do {
            try Task.checkCancellation()
            var modified:Date?
            if !force,let cached,let oldDate=cached.modified,cached.format != nil,cached.sourceIsNetwork != nil,cached.bitrate != nil,(!cached.isLossless || cached.bitDepth != nil) {
                var info=stat()
                let result=file.url.withUnsafeFileSystemRepresentation { path in path.map { Darwin.lstat($0,&info) } ?? -1 }
                guard result == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSFilePathErrorKey:file.url.path]) }
                let date=Date(timeIntervalSince1970:Double(info.st_mtimespec.tv_sec)+Double(info.st_mtimespec.tv_nsec)/1_000_000_000)
                if abs(oldDate.timeIntervalSince(date)) < 0.000001,cached.fileSize == info.st_size { return .init(file:file,unchanged:true) }
                modified=date
            }
            var track=try await MetadataReader.read(file.url,sidecars:file)
            try Task.checkCancellation()
            if let modified { track.modified=modified }
            return .init(file:file,track:track)
        } catch { return .init(file:file,error:error.localizedDescription) }
    }
}
