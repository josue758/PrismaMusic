import Foundation

struct LibraryQueryKey: Hashable {
    var revision:Int
    var search:String
    var artist:String
    var genre:String
    var year:String
    var section:String
    var sort:String
}
final class LibraryQueryCache {
    let tracks:[Track]
    let indices:[String:Int]
    lazy var albums:[(key:String,value:[Track])]=Dictionary(grouping:tracks) { $0.artist+"\u{1f}"+$0.album }.sorted { $0.key < $1.key }
    lazy var artists:[(key:String,value:[Track])]=Dictionary(grouping:tracks,by:\.artist).sorted { $0.key < $1.key }
    init(tracks:[Track]) { self.tracks=tracks; indices=Dictionary(tracks.enumerated().map { ($0.element.id,$0.offset) },uniquingKeysWith:{ first,_ in first }) }
}
struct LibraryStatistics {
    var albumCount:Int
    var artists:[String]
    var genres:[String]
    var years:[String]
    var bytes:Int64=0
    var duration:Double=0
    var withArtwork=0
    var withLyrics=0
    init(tracks:[Track]) {
        var albums=Set<String>(),artistSet=Set<String>(),genreSet=Set<String>(),yearSet=Set<String>()
        for track in tracks {
            albums.insert(track.artist+"\u{1f}"+track.album); artistSet.insert(track.artist); genreSet.insert(track.genre)
            if !track.year.isEmpty { yearSet.insert(track.year) }
            bytes += track.fileSize ?? 0; duration += track.duration
            if track.hasArtwork { withArtwork += 1 }; if track.lyrics != nil { withLyrics += 1 }
        }
        albumCount=albums.count; artists=artistSet.sorted(); genres=genreSet.sorted(); years=yearSet.sorted().reversed()
    }
}
