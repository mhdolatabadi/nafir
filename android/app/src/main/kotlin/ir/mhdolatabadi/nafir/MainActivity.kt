package ir.mhdolatabadi.nafir

import com.ryanheise.audioservice.AudioServiceActivity

// Shares the Flutter engine with audio_service's background playback service,
// so music keeps playing and responds to media controls with the app closed.
class MainActivity : AudioServiceActivity()
