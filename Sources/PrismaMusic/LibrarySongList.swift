import SwiftUI

struct LibrarySongList:View {
    @EnvironmentObject var store:LibraryStore
    var tracks:[Track]
    var showAlbum=true
    var subtitleAlbum=false
    var number:(Track)->Int
    @State private var selectedID:String?
    @State private var editing:Track?
    var body:some View {
        LazyVStack(spacing:3) {
            HStack(spacing:10) {
                Text("#").frame(width:22)
                Color.clear.frame(width:40,height:1)
                Text(store.t("title")).frame(maxWidth:.infinity,alignment:.leading)
                if showAlbum { Text(store.t("album")).frame(width:140,alignment:.leading); Text(store.t("year")).frame(width:38) }
                Image(systemName:"clock").frame(width:38)
                Color.clear.frame(width:54,height:1)
            }.font(.system(size:9,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,12).padding(.bottom,9).accessibilityHidden(true)
            ForEach(tracks) { track in
                HStack(spacing:10) {
                    Button { store.play(track,in:tracks) } label: {
                        Group {
                            if store.loadingTrackID == track.id { ProgressView().controlSize(.mini) }
                            else if store.currentID == track.id && store.isPlaying { Image(systemName:"waveform").foregroundStyle(store.effectiveAccent) }
                            else { Text(String(format:"%02d",number(track))).foregroundStyle(.secondary) }
                        }.font(.system(size:10,design:.monospaced)).frame(width:22,height:34)
                    }.buttonStyle(.plain).help(store.t("play")).accessibilityLabel(store.t("play")+": "+track.title)
                    ArtworkView(track:track).frame(width:40,height:40)
                    VStack(alignment:.leading,spacing:5) {
                        HStack(spacing:7) {
                            Text(track.title).font(.system(size:12,weight:.medium)).foregroundStyle(store.currentID == track.id ? store.effectiveAccent : .primary)
                            if store.preferences.showQuality && showAlbum { QualityBadge(track:track) }
                        }
                        Text((subtitleAlbum ? store.displayAlbum(track.album) : store.displayArtist(track.artist))+(store.preferences.showQuality && !track.qualitySummary.isEmpty ? " · "+track.qualitySummary : "")).font(.system(size:9)).foregroundStyle(.secondary)
                    }.lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                    if showAlbum { Text(store.displayAlbum(track.album)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).frame(width:140,alignment:.leading); Text(track.year).font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary).frame(width:38) }
                    Text(clockText(track.duration)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).frame(width:38)
                    FavoriteControl(track:track).frame(width:22)
                    Button { store.inspectedID=track.id; store.showInfo=true; store.showLyrics=false; store.showQueue=false } label: { Image(systemName:"info.circle").frame(width:22,height:28) }.buttonStyle(.plain).foregroundStyle(.secondary).help(store.t("fileInfo"))
                }.padding(.horizontal,12).padding(.vertical,store.preferences.compactRows ? 5 : 9)
                    .background(selectedID == track.id ? store.effectiveAccent.opacity(0.13) : number(track)%2 == 1 ? .primary.opacity(0.03) : .clear,in:RoundedRectangle(cornerRadius:12))
                    .contentShape(Rectangle()).onTapGesture(count:2) { store.play(track,in:tracks) }.onTapGesture { selectedID=track.id; store.inspectedID=track.id }
                    .contextMenu { TrackContextMenu(track:track) { editing=track } }
            }
        }.sheet(item:$editing) { TagEditor(track:$0).environmentObject(store) }
    }
}
