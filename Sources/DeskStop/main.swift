import AppKit

#if DEBUG
// `--render-ui <dir>`: draw the panel and Settings from fixture data into
// PNGs and exit, before anything below touches the desktop or saved data.
if let flag = CommandLine.arguments.firstIndex(of: "--render-ui"),
   flag + 1 < CommandLine.arguments.count {
    UIPreviewRenderer.run(outputDirectory: CommandLine.arguments[flag + 1])
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
