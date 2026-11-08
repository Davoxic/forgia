import Foundation
import AVFoundation

/// Quando iOS mostra la richiesta di installazione, Forgia passa in background
/// ma il server deve restare in piedi per consegnare l'IPA. Un flusso audio muto
/// in loop tiene il processo attivo: è l'unico modo supportato per farlo senza
/// permessi particolari.
final class BackgroundKeeper {
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers: non interrompe la musica che stai ascoltando.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(data: Self.silentWAV())
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            self.player = player
        } catch {
            // Senza audio il server regge comunque qualche decina di secondi.
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Un WAV PCM di un secondo di silenzio, costruito a mano.
    private static func silentWAV(seconds: Int = 1, sampleRate: Int = 8000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let dataSize = byteRate * seconds

        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func le32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func le16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF"); le32(36 + dataSize); ascii("WAVE")
        ascii("fmt "); le32(16); le16(1); le16(channels)
        le32(sampleRate); le32(byteRate)
        le16(channels * bitsPerSample / 8); le16(bitsPerSample)
        ascii("data"); le32(dataSize)
        data.append(Data(repeating: 0, count: dataSize))
        return data
    }
}
