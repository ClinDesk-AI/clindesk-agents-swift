import Foundation

public enum ModelTool: Equatable, Sendable {
    case function(ToolDescriptor)
    case computer(ComputerToolDescriptor)
    case localShell(LocalShellToolDescriptor)
    case shell(ShellToolDescriptor)
    case applyPatch(ApplyPatchToolDescriptor)
    case custom(CustomToolDescriptor)
}

public enum Tool<Context: Sendable>: Sendable {
    case function(FunctionTool<Context>)
    case computer(ComputerTool<Context>)
    case localShell(LocalShellTool<Context>)
    case shell(ShellTool<Context>)
    case applyPatch(ApplyPatchTool<Context>)
    case custom(CustomTool<Context>)

    public var name: String {
        switch self {
        case .function(let tool):
            return tool.descriptor.name
        case .computer(let tool):
            return tool.name
        case .localShell(let tool):
            return tool.name
        case .shell(let tool):
            return tool.name
        case .applyPatch(let tool):
            return tool.name
        case .custom(let tool):
            return tool.name
        }
    }

    public var modelTool: ModelTool {
        switch self {
        case .function(let tool):
            return .function(tool.descriptor)
        case .computer(let tool):
            return .computer(tool.modelDescriptor)
        case .localShell(let tool):
            return .localShell(tool.descriptor)
        case .shell(let tool):
            return .shell(tool.descriptor)
        case .applyPatch(let tool):
            return .applyPatch(tool.descriptor)
        case .custom(let tool):
            return .custom(tool.descriptor)
        }
    }

    public var functionTool: FunctionTool<Context>? {
        if case .function(let tool) = self {
            return tool
        }
        return nil
    }

    public var customTool: CustomTool<Context>? {
        if case .custom(let tool) = self {
            return tool
        }
        return nil
    }

    public var localShellTool: LocalShellTool<Context>? {
        if case .localShell(let tool) = self {
            return tool
        }
        return nil
    }

    public var computerTool: ComputerTool<Context>? {
        if case .computer(let tool) = self {
            return tool
        }
        return nil
    }

    public var shellTool: ShellTool<Context>? {
        if case .shell(let tool) = self {
            return tool
        }
        return nil
    }

    public var applyPatchTool: ApplyPatchTool<Context>? {
        if case .applyPatch(let tool) = self {
            return tool
        }
        return nil
    }
}
