import ArgumentParser
import HidLensCore

@main
struct HidLensCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hidlens",
        abstract: "macOS USB Polling Rate Override & Diagnostic Tool",
        discussion: """
        HidLens is the macOS equivalent of hidusbf — override USB polling rates \
        for game controllers and mice via a kernel extension.

        For polling rate override, the HidLens KEXT must be loaded.
        Run 'hidlens setup' for instructions.
        """,
        version: "1.0.0",
        subcommands: [
            ListCommand.self,
            InspectCommand.self,
            MeasureCommand.self,
            OverrideCommand.self,
            ResetCommand.self,
            ExportCommand.self,
            SetupCommand.self
        ],
        defaultSubcommand: ListCommand.self
    )
}

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Show KEXT installation and setup instructions"
    )

    func run() {
        print(KextInstaller.setupInstructions)
    }
}
