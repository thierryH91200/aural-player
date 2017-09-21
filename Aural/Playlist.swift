/*
    Encapsulates all CRUD logic for a playlist
 */
import Foundation
import AVFoundation

class Playlist: PlaylistCRUDProtocol {
    
    private var tracks: [Track] = [Track]()
    
    // A map to quickly look up tracks by (absolute) file path (used when adding tracks, to avoid duplicates)
    private var tracksByFilePath: [String: Track] = [String: Track]()
    
    func getTracks() -> [Track] {
        return tracks
    }
    
    func peekTrackAt(_ index: Int?) -> IndexedTrack? {
        let invalidIndex: Bool = index == nil || index! < 0 || index! >= tracks.count
        return invalidIndex ? nil : IndexedTrack(tracks[index!], index!)
    }
    
    func size() -> Int {
        return tracks.count
    }
    
    func totalDuration() -> Double {
        
        var totalDuration: Double = 0
        
        for track in tracks {
            totalDuration += track.duration
        }
        
        return totalDuration
    }
    
    func summary() -> (size: Int, totalDuration: Double) {
        return (tracks.count, totalDuration())
    }
    
    func addTrack(_ track: Track) -> Int {
        
        if (!trackExists(track)) {
            doAddTrack(track)
            return tracks.count - 1
        }
        
        // This means nothing was added
        return -1
    }
    
    private func doAddTrack(_ track: Track) {
        tracks.append(track)
        tracksByFilePath[track.file.path] = track
    }
    
    // Checks whether or not a track with the given absolute file path already exists.
    private func trackExists(_ track: Track) -> Bool {
        return tracksByFilePath[track.file.path] != nil
    }
    
    func removeTrack(_ index: Int) {
        
        let track: Track? = tracks[index]
        
        if (track != nil) {
            tracksByFilePath.removeValue(forKey: track!.file.path)
            tracks.remove(at: index)
        }
    }
    
    func indexOfTrack(_ track: Track?) -> Int?  {
        
        if (track == nil) {
            return nil
        }
        
        return tracks.index(where: {$0 == track})
    }
    
    func clear() {
        tracks.removeAll()
        tracksByFilePath.removeAll()
    }
    
    func save(_ file: URL) {
        PlaylistIO.savePlaylist(file)
    }
    
    func moveTrackUp(_ index: Int) -> Int {
        
        if (index <= 0) {
            return index
        }
        
        let upIndex = index - 1
        swapTracks(index, upIndex)
        return upIndex
    }
    
    func moveTrackDown(_ index: Int) -> Int {
        
        if (index >= (tracks.count - 1)) {
            return index
        }
        
        let downIndex = index + 1
        swapTracks(index, downIndex)
        return downIndex
    }
    
    // Swaps two tracks in the array of tracks
    private func swapTracks(_ trackIndex1: Int, _ trackIndex2: Int) {
        swap(&tracks[trackIndex1], &tracks[trackIndex2])
    }
    
    func search(_ searchQuery: SearchQuery) -> SearchResults {
        
        var results: [SearchResult] = [SearchResult]()
        var resultIndex = 1
        
        for i in 0...tracks.count - 1 {
            
            let track = tracks[i]
            let match = trackMatchesQuery(track: track, searchQuery: searchQuery)
            
            if (match.matched) {
                results.append(SearchResult(resultIndex: resultIndex, trackIndex: i, match: (match.matchedField!, match.matchedFieldValue!)))
                resultIndex += 1
            }
        }
        
        return SearchResults(results: results)
    }
    
    // Checks if a single track matches search criteria, and returns information about the match, if there is one
    private func trackMatchesQuery(track: Track, searchQuery: SearchQuery) -> (matched: Bool, matchedField: String?, matchedFieldValue: String?) {
        
        let caseSensitive: Bool = searchQuery.options.caseSensitive
        
        let queryText: String = caseSensitive ? searchQuery.text : searchQuery.text.lowercased()
        
        // Actual track fields to compare to query text
        // FieldName -> (OriginalFieldValue, FieldValueForComparison)
        // FieldValueForComparison is used for the comparison (and may have different case than OriginalFieldValue), while OriginalFieldValue is returned in the result if there is a match
        var trackFields: [String: (original: String, compared: String)] = [String: (String, String)]()
        
        // Add name field if included in search
        if (searchQuery.fields.name) {
            
            // Check both the filename and the display name
            
            let lastPathComponent = track.file.deletingPathExtension().lastPathComponent
            
            trackFields["Filename"] = (lastPathComponent, caseSensitive ? lastPathComponent : lastPathComponent.lowercased())
            
            let displayName = track.conciseDisplayName
            trackFields["Name"] = (displayName, caseSensitive ? displayName : displayName.lowercased())
        }
        
        // Add artist field if included in search
        if (searchQuery.fields.artist) {
            
            if let artist = track.displayInfo.artist {
                trackFields["Artist"] = (artist, caseSensitive ? artist : artist.lowercased())
            }
        }
        
        // Add title field if included in search
        if (searchQuery.fields.title) {
            
            if let title = track.displayInfo.title {
                trackFields["Title"] = (title, caseSensitive ? title : title.lowercased())
            }
        }
        
        // Add album field if included in search
        if (searchQuery.fields.album) {
            
            // Make sure album info has been loaded (it is loaded lazily)
            MetadataReader.loadSearchMetadata(track)
            
            if let album = track.metadata[AVMetadataCommonKeyAlbumName]?.value {
                trackFields["Album"] = (album, caseSensitive ? album : album.lowercased())
            }
        }
        
        // Check each field value against the search query text
        for (key: field, value: (original: original, compared: compared)) in trackFields {
            
            switch searchQuery.type {
                
            case .beginsWith: if compared.hasPrefix(queryText) {
                return (true, field, original)
                }
                
            case .endsWith: if compared.hasSuffix(queryText) {
                return (true, field, original)
                }
                
            case .equals: if compared == queryText {
                return (true, field, original)
                }
                
            case .contains: if compared.range(of: queryText) != nil {
                return (true, field, original)
                }
            }
        }
        
        // Didn't match
        return (false, nil, nil)
    }
    
    func sort(_ sort: Sort) {
        
        switch sort.field {
            
        // Sort by name
        case .name: if sort.order == SortOrder.ascending {
            tracks.sort(by: compareTracks_ascendingByName)
        } else {
            tracks.sort(by: compareTracks_descendingByName)
            }
            
        // Sort by duration
        case .duration: if sort.order == SortOrder.ascending {
            tracks.sort(by: compareTracks_ascendingByDuration)
        } else {
            tracks.sort(by: compareTracks_descendingByDuration)
            }
        }
    }
    
    // Comparison functions for different sort criteria
    
    func compareTracks_ascendingByName(aTrack: Track, anotherTrack: Track) -> Bool {
        return aTrack.conciseDisplayName.compare(anotherTrack.conciseDisplayName) == ComparisonResult.orderedAscending
    }
    
    func compareTracks_descendingByName(aTrack: Track, anotherTrack: Track) -> Bool {
        return aTrack.conciseDisplayName.compare(anotherTrack.conciseDisplayName) == ComparisonResult.orderedDescending
    }
    
    func compareTracks_ascendingByDuration(aTrack: Track, anotherTrack: Track) -> Bool {
        return aTrack.duration < anotherTrack.duration
    }
    
    func compareTracks_descendingByDuration(aTrack: Track, anotherTrack: Track) -> Bool {
        return aTrack.duration > anotherTrack.duration
    }
    
    // Returns all state for this playlist that needs to be persisted to disk
    func persistentState() -> PlaylistState {
        
        let state = PlaylistState()
        
        for track in tracks {
            state.tracks.append(track.file)
        }
        
        return state
    }
}
