import os

public enum HidLensLog {
    private static let subsystem = "com.hidlens.app"

    public static let enumeration = Logger(subsystem: subsystem, category: "enumeration")
    public static let measurement = Logger(subsystem: subsystem, category: "measurement")
    public static let driver = Logger(subsystem: subsystem, category: "driver")
    public static let export_ = Logger(subsystem: subsystem, category: "export")
}
