import Foundation

struct RecordingHUDActions {
    let onStop: () -> Void
    let onOpenWindow: () -> Void
    let onOpenNotes: () -> Void
    let onOpenConfig: () -> Void
    let onOpenLog: () -> Void
    let onQuit: () -> Void
}
