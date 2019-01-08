// SPDX-License-Identifier: MIT
// Copyright © 2018 WireGuard LLC. All Rights Reserved.

import Cocoa

class StatusMenu: NSMenu {

    let tunnelsManager: TunnelsManager
    var tunnelStatusObservers = [AnyObject]()

    var statusMenuItem: NSMenuItem?
    var networksMenuItem: NSMenuItem?
    var firstTunnelMenuItemIndex: Int = 0
    var numberOfTunnelMenuItems: Int = 0

    var manageTunnelsRootVC: ManageTunnelsRootViewController?
    lazy var manageTunnelsWindow: NSWindow = {
        manageTunnelsRootVC = ManageTunnelsRootViewController(tunnelsManager: tunnelsManager)
        let window = NSWindow(contentViewController: manageTunnelsRootVC!)
        window.title = tr("macWindowTitleManageTunnels")
        window.setFrameAutosaveName(NSWindow.FrameAutosaveName("ManageTunnelsWindow")) // Auto-save window position and size
        return window
    }()

    init(tunnelsManager: TunnelsManager) {
        self.tunnelsManager = tunnelsManager
        super.init(title: "WireGuard Status Bar Menu")

        addStatusMenuItems()
        addItem(NSMenuItem.separator())
        for index in 0 ..< tunnelsManager.numberOfTunnels() {
            let isUpdated = updateStatusMenuItems(with: tunnelsManager.tunnel(at: index), ignoreInactive: true)
            if isUpdated {
                break
            }
        }

        firstTunnelMenuItemIndex = numberOfItems
        let isAdded = addTunnelMenuItems()
        if isAdded {
            addItem(NSMenuItem.separator())
        }
        addTunnelManagementItems()
    }

    required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addStatusMenuItems() {
        let statusTitle = tr(format: "macStatus (%@)", tr("tunnelStatusInactive"))
        let statusMenuItem = NSMenuItem(title: statusTitle, action: #selector(manageTunnelsClicked), keyEquivalent: "")
        statusMenuItem.isEnabled = false
        addItem(statusMenuItem)
        let networksMenuItem = NSMenuItem(title: tr("macMenuNetworksInactive"), action: #selector(manageTunnelsClicked), keyEquivalent: "")
        networksMenuItem.isEnabled = false
        addItem(networksMenuItem)
        self.statusMenuItem = statusMenuItem
        self.networksMenuItem = networksMenuItem
    }

    @discardableResult
    func updateStatusMenuItems(with tunnel: TunnelContainer, ignoreInactive: Bool) -> Bool {
        guard let statusMenuItem = statusMenuItem, let networksMenuItem = networksMenuItem else { return false }
        var statusText: String

        switch tunnel.status {
        case .waiting:
            return false
        case .inactive:
            if ignoreInactive {
                return false
            }
            statusText = tr("tunnelStatusInactive")
        case .activating:
            statusText = tr("tunnelStatusActivating")
        case .active:
            statusText = tr("tunnelStatusActive")
        case .deactivating:
            statusText = tr("tunnelStatusDeactivating")
        case .reasserting:
            statusText = tr("tunnelStatusReasserting")
        case .restarting:
            statusText = tr("tunnelStatusRestarting")
        }

        statusMenuItem.title = tr(format: "macStatus (%@)", statusText)

        let addresses = tunnel.tunnelConfiguration?.interface.addresses ?? []
        let addressesString = addresses.map { $0.stringRepresentation }.joined(separator: ", ")
        if addressesString.isEmpty {
            networksMenuItem.title = tr("macMenuNetworksNone")
        } else {
            networksMenuItem.title = tr(format: "macMenuNetworks (%@)", addressesString)
        }
        return true
    }

    func addTunnelMenuItems() -> Bool {
        let numberOfTunnels = tunnelsManager.numberOfTunnels()
        for index in 0 ..< tunnelsManager.numberOfTunnels() {
            let tunnel = tunnelsManager.tunnel(at: index)
            insertTunnelMenuItem(for: tunnel, at: numberOfTunnelMenuItems)
        }
        return numberOfTunnels > 0
    }

    func addTunnelManagementItems() {
        let manageItem = NSMenuItem(title: tr("macMenuManageTunnels"), action: #selector(manageTunnelsClicked), keyEquivalent: "")
        manageItem.target = self
        addItem(manageItem)
        let importItem = NSMenuItem(title: tr("macMenuImportTunnels"), action: #selector(importTunnelsClicked), keyEquivalent: "")
        importItem.target = self
        addItem(importItem)
    }

    @objc func tunnelClicked(sender: AnyObject) {
        guard let tunnelMenuItem = sender as? NSMenuItem else { return }
        guard let tunnel = tunnelMenuItem.representedObject as? TunnelContainer else { return }
        if tunnelMenuItem.state == .off {
            tunnelsManager.startActivation(of: tunnel)
        } else {
            tunnelsManager.startDeactivation(of: tunnel)
        }
    }

    @objc func manageTunnelsClicked() {
        NSApp.activate(ignoringOtherApps: true)
        manageTunnelsWindow.makeKeyAndOrderFront(self)
    }

    @objc func importTunnelsClicked() {
        NSApp.activate(ignoringOtherApps: true)
        manageTunnelsWindow.makeKeyAndOrderFront(self)
        ImportPanelPresenter.presentImportPanel(tunnelsManager: tunnelsManager, sourceVC: manageTunnelsRootVC!)
    }
}

extension StatusMenu {
    func insertTunnelMenuItem(for tunnel: TunnelContainer, at tunnelIndex: Int) {
        let menuItem = NSMenuItem(title: tunnel.name, action: #selector(tunnelClicked(sender:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = tunnel
        updateTunnelMenuItem(menuItem)
        let statusObservationToken = tunnel.observe(\.status) { [weak self] tunnel, _ in
            updateTunnelMenuItem(menuItem)
            self?.updateStatusMenuItems(with: tunnel, ignoreInactive: false)
        }
        tunnelStatusObservers.insert(statusObservationToken, at: tunnelIndex)
        insertItem(menuItem, at: firstTunnelMenuItemIndex + tunnelIndex)
        if numberOfTunnelMenuItems == 0 {
            insertItem(NSMenuItem.separator(), at: firstTunnelMenuItemIndex + tunnelIndex + 1)
        }
        numberOfTunnelMenuItems += 1
    }

    func removeTunnelMenuItem(at tunnelIndex: Int) {
        removeItem(at: firstTunnelMenuItemIndex + tunnelIndex)
        tunnelStatusObservers.remove(at: tunnelIndex)
        numberOfTunnelMenuItems -= 1
        if numberOfTunnelMenuItems == 0 {
            if let firstItem = item(at: firstTunnelMenuItemIndex), firstItem.isSeparatorItem {
                removeItem(at: firstTunnelMenuItemIndex)
            }
        }
    }

    func moveTunnelMenuItem(from oldTunnelIndex: Int, to newTunnelIndex: Int) {
        let oldMenuItem = item(at: firstTunnelMenuItemIndex + oldTunnelIndex)!
        let oldMenuItemTitle = oldMenuItem.title
        let oldMenuItemTunnel = oldMenuItem.representedObject
        removeItem(at: firstTunnelMenuItemIndex + oldTunnelIndex)
        let menuItem = NSMenuItem(title: oldMenuItemTitle, action: #selector(tunnelClicked(sender:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = oldMenuItemTunnel
        insertItem(menuItem, at: firstTunnelMenuItemIndex + newTunnelIndex)
        let statusObserver = tunnelStatusObservers.remove(at: oldTunnelIndex)
        tunnelStatusObservers.insert(statusObserver, at: newTunnelIndex)
    }
}

private func updateTunnelMenuItem(_ tunnelMenuItem: NSMenuItem) {
    guard let tunnel = tunnelMenuItem.representedObject as? TunnelContainer else { return }
    tunnelMenuItem.title = tunnel.name
    let shouldShowCheckmark = (tunnel.status != .inactive && tunnel.status != .deactivating)
    tunnelMenuItem.state = shouldShowCheckmark ? .on : .off
}

extension StatusMenu: TunnelsManagerListDelegate {
    func tunnelAdded(at index: Int) {
        let tunnel = tunnelsManager.tunnel(at: index)
        insertTunnelMenuItem(for: tunnel, at: index)
        manageTunnelsRootVC?.tunnelsListVC?.tunnelAdded(at: index)
    }

    func tunnelModified(at index: Int) {
        if let tunnelMenuItem = item(at: firstTunnelMenuItemIndex + index) {
            updateTunnelMenuItem(tunnelMenuItem)
        }
        manageTunnelsRootVC?.tunnelsListVC?.tunnelModified(at: index)
    }

    func tunnelMoved(from oldIndex: Int, to newIndex: Int) {
        moveTunnelMenuItem(from: oldIndex, to: newIndex)
        manageTunnelsRootVC?.tunnelsListVC?.tunnelMoved(from: oldIndex, to: newIndex)
    }

    func tunnelRemoved(at index: Int) {
        removeTunnelMenuItem(at: index)
        manageTunnelsRootVC?.tunnelsListVC?.tunnelRemoved(at: index)
    }
}

extension StatusMenu: TunnelsManagerActivationDelegate {
    func tunnelActivationAttemptFailed(tunnel: TunnelContainer, error: TunnelsManagerActivationAttemptError) {
        if let manageTunnelsRootVC = manageTunnelsRootVC, manageTunnelsWindow.isVisible {
            ErrorPresenter.showErrorAlert(error: error, from: manageTunnelsRootVC)
        } else {
            ErrorPresenter.showErrorAlert(error: error, from: nil)
        }
    }

    func tunnelActivationAttemptSucceeded(tunnel: TunnelContainer) {
        // Nothing to do
    }

    func tunnelActivationFailed(tunnel: TunnelContainer, error: TunnelsManagerActivationError) {
        if let manageTunnelsRootVC = manageTunnelsRootVC, manageTunnelsWindow.isVisible {
            ErrorPresenter.showErrorAlert(error: error, from: manageTunnelsRootVC)
        } else {
            ErrorPresenter.showErrorAlert(error: error, from: nil)
        }
    }

    func tunnelActivationSucceeded(tunnel: TunnelContainer) {
        // Nothing to do
    }
}