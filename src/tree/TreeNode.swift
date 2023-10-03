class TreeNode: Equatable {
    private var _children: [TreeNode] = []
    var children: [TreeNode] { _children }
    fileprivate weak var _parent: TreeNode? = nil
    var parent: TreeNode? { _parent }
    private var adaptiveWeight: CGFloat
    private var _mostRecentChild: TreeNode?
    var mostRecentChild: TreeNode? { _mostRecentChild ?? children.first }

    init(parent: TreeNode, adaptiveWeight: CGFloat) {
        self.adaptiveWeight = adaptiveWeight
        bindTo(parent: parent, adaptiveWeight: adaptiveWeight)
    }

    fileprivate init() {
        adaptiveWeight = 0
    }

    /// See: ``getWeight(_:)``
    func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        switch parent?.kind {
        case .tilingContainer(let parent):
            if parent.orientation == targetOrientation {
                adaptiveWeight = newValue
            } else {
                error("You can't change \(targetOrientation) weight of nodes located in \(parent.orientation) container")
            }
        case .workspace:
            error("Can't change weight for floating windows and workspace root containers")
        case .window:
            error("Windows can't be parent containers")
        case nil:
            error("Can't change weight if TreeNode doesn't have parent")
        }
    }

    /// Weight itself doesn't make sense. The parent container controls semantics of weight
    func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        switch parent?.kind {
        case .tilingContainer(let parent):
            return parent.orientation == targetOrientation ? adaptiveWeight : parent.getWeight(targetOrientation)
        case .workspace(let parent):
            switch self.kind {
            case .window: // self is a floating window
                error("Weight doesn't make sense for floating windows")
            case .tilingContainer: // root tiling container
                precondition(self is TilingContainer)
                return parent.getWeight(targetOrientation)
            case .workspace:
                error("Workspaces can't be child")
            }
        case .window:
            error("Windows can't be parent containers")
        case nil:
            error("Weight doesn't make sense for containers without parent")
        }
    }

    @discardableResult
    func bindTo(parent newParent: TreeNode, adaptiveWeight: CGFloat, index: Int = -1) -> PreviousBindingData? {
        if _parent === newParent {
            error("Binding to the same parent doesn't make sense")
        }
        if newParent is Window {
            error("Windows can't have children")
        }
        let result = unbindIfPossible()

        if newParent === NilTreeNode.instance {
            return result
        }
        if adaptiveWeight == WEIGHT_AUTO {
            switch newParent.kind {
            case .tilingContainer(let newParent):
                self.adaptiveWeight = newParent.children.sumOf { $0.getWeight(newParent.orientation) }
                    .div(newParent.children.count)
                    ?? 1
            case .workspace:
                switch self.kind {
                case .window:
                    self.adaptiveWeight = WEIGHT_FLOATING
                case .tilingContainer:
                    self.adaptiveWeight = 1
                case .workspace:
                    error("Binding workspace to workspace is illegal")
                }
            case .window:
                error("Windows can't have children")
            }
        } else {
            self.adaptiveWeight = adaptiveWeight
        }
        let window = anyLeafWindowRecursive
        let newParentWorkspace = newParent.workspace
        // "effectively empty" -> not "effectively empty" transition
        if let window, newParentWorkspace.assignedMonitor == nil {
            newParentWorkspace.assignedMonitor = window.getCenter()?.monitorApproximation
            //?? NSScreen.focusedMonitorOrNilIfDesktop // todo uncomment once Monitor mock is done
            //?? errorT("Can't set assignedMonitor") // todo uncomment once Monitor mock is done
        }
        newParent._children.insert(self, at: index == -1 ? newParent._children.count : index)
        _parent = newParent
        markAsMostRecentChild()
        // Update currentEmptyWorkspace since it's no longer effectively empty
        if window != nil && newParentWorkspace == currentEmptyWorkspace {
            currentEmptyWorkspace = getOrCreateNextEmptyWorkspace()
        }
        return result
    }

    private func unbindIfPossible() -> PreviousBindingData? {
        guard let _parent else { return nil }
        let workspace = workspace

        let index = _parent._children.remove(element: self) ?? errorT("Can't find child in its parent")
        // todo lock screen -> windows are reset
        if _parent._mostRecentChild == self {
            _parent._mostRecentChild = nil
        }
        self._parent = nil

        if workspace.isEffectivelyEmpty { // It became empty
            currentEmptyWorkspace = workspace
            currentEmptyWorkspace.assignedMonitor = nil
        }
        return PreviousBindingData(adaptiveWeight: adaptiveWeight, index: index)
    }

    func markAsMostRecentChild() {
        guard let _parent else { return }
        _parent._mostRecentChild = self
        _parent.markAsMostRecentChild()
    }

    @discardableResult
    func unbindFromParent() -> PreviousBindingData {
        unbindIfPossible() ?? errorT("\(self) is already unbinded")
    }

    static func ==(lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs === rhs
    }


    @discardableResult
    func focus() -> Bool { error("Not implemented") }
    func getRect() -> Rect? { error("Not implemented") }
}

private let WEIGHT_FLOATING = CGFloat(-2)
/// Splits containers evenly if tiling.
///
/// Reset weight is bind to workspace (aka "floating windows")
let WEIGHT_AUTO = CGFloat(-1)

struct PreviousBindingData {
    let adaptiveWeight: CGFloat
    let index: Int
}

class NilTreeNode: TreeNode {
    private override init() {
        super.init()
    }
    static let instance = NilTreeNode()
}