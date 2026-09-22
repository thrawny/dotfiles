pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink?.audio ?? null
    readonly property bool available: audio !== null
    readonly property bool muted: audio?.muted ?? false
    readonly property int percent: Math.round((audio?.volume ?? 0) * 100)
    readonly property string description: sink?.description ?? "No audio output"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    function toggleMute(): void {
        if (audio)
            audio.muted = !audio.muted;
    }
    function adjust(delta: real): void {
        if (audio)
            audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
    }
}
