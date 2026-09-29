# Apple Speech

The collapsible Apple models group inside Settings → Local → Speech to text includes the languages reported by macOS SpeechTranscriber on supported Macs running macOS 26 or later. Installed language assets show Use; other languages show Install. macOS manages downloads. Native entries have no invented memory, speed or quality estimates and appear as a selectable unrated entry in the comparison chart.

Selection persists through the existing local transcription settings. The native model identifier and managed route dispatch to SpeechAnalyzer without starting Python or sending an HTTP request. Selecting native speech disables credit routing. Text cleanup retains its selected provider, so choose Verbatim if the entire dictation must stay local.

`--verify-native-speech` checks recorded PCM integrity, malformed input rejection, hidden picker controls, preview isolation and read-only system language availability. It does not request permissions or download assets.

For a real transcription check, generate an isolated audio fixture with `say -v Samantha -o /tmp/s2t-native-generated.aiff 'The blue square is next to the yellow circle.'`, then run the packaged app executable with `--verify-native-speech --native-speech-fixture /tmp/s2t-native-generated.aiff`. This requires English US assets already installed. It checks recognition, timestamp output and cancellation without microphone, screen or clipboard access.

Also run `bash scripts/test.sh`, package with `bash scripts/build-app.sh`, and run `--verify-local-models`, `--verify-models-window`, and `--verify-build` against build/S2T.app.
