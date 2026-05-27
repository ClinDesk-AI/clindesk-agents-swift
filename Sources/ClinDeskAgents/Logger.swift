import OSLog

public enum AgentsLogger {
    public static let subsystem = "com.clindesk.agents"
    public static let category = "ClinDeskAgents"
    public static let shared = Logger(subsystem: subsystem, category: category)
}
