//
//  ContainerViewController.swift
//  md-preview
//
//  Plain-NSView wrapper around `MainSplitViewController`. Exists so that
//  WindowChromeController and FileDropController can add their hover-tracker,
//  window-drag, and drop-target overlays as ordinary sibling subviews of the
//  split view. NSSplitView (the controller's own root view) reorders its
//  arranged subviews during layout, which made overlays added directly to it
//  unreliable for hit-testing — particularly the title-bar drag region.
//

import Cocoa

final class ContainerViewController: NSViewController {

    let splitViewController = MainSplitViewController()

    override func loadView() {
        // Plain NSView container. Do NOT set
        // `translatesAutoresizingMaskIntoConstraints = false` here — when
        // this view is installed as the window's contentView, AppKit
        // resizes it via autoresizing masks, not auto layout.
        let container = NSView()
        view = container

        addChild(splitViewController)
        let splitView = splitViewController.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }
}
