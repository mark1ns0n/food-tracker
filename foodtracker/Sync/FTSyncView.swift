//
//  FTSyncView.swift
//  foodtracker
//
//  F01.15 — the only new screen: connect the device, watch the log move.
//

import AppShell
import CoreSync
import SwiftUI

/// The Sync tab. It exists so this app can become the *second* device on an
/// account, which is what the F01.15 acceptance needs and what no card before
/// it created. It dies with the app in F01.19.
struct FTSyncView: View {
    /// `nil` only in previews — the app always has one. Whether it can actually
    /// do anything is `isAvailable`, which is false when `SyncBootstrap` would
    /// not compose (keychain trouble). The tab stays visible either way and
    /// explains itself, because a missing tab looks like a missing feature
    /// rather than a failure.
    let controller: FTSyncController?

    var body: some View {
        NavigationStack {
            Group {
                if let controller, controller.isAvailable {
                    FTSyncForm(controller: controller)
                } else {
                    ContentUnavailableView(
                        "Sync Unavailable",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text(
                            """
                            This device could not open its secure storage, so it \
                            cannot connect to the backend. Everything else keeps \
                            working offline.
                            """
                        )
                    )
                }
            }
            .navigationTitle("Sync")
        }
    }
}

private struct FTSyncForm: View {
    @ObservedObject var controller: FTSyncController

    /// The log stands behind the tables only once the import has run (F01.11),
    /// and nothing syncs before it does.
    @AppStorage(FTBackfillService.doneKey) private var backfillDone = false

    var body: some View {
        Form {
            deviceSection
            logSection
        }
        .onAppear {
            controller.refresh()
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent("Status", value: statusText)

            if !controller.isEnrolled {
                // Pasted rather than scanned: this app has no camera flow and no
                // URL scheme of its own — `superapp://` belongs to the shell. The
                // portal's https link works as plain text.
                TextField("Connection link", text: $controller.enrollmentLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .keyboardType(.URL)

                Button("Connect") {
                    controller.enroll()
                }
                .disabled(controller.enrollmentLink.trimmingCharacters(in: .whitespaces).isEmpty)

                Link("Open the devices portal", destination: controller.portalURL)
            }

            if let code = matchingCode {
                LabeledContent("Confirmation code", value: code)
            }
        } header: {
            Text("Device")
        } footer: {
            Text(
                controller.isEnrolled
                    ? "Groceries, delivery and fasting are shared with your other devices."
                    : "Create a device on the portal, then paste the link it gives you."
            )
        }
    }

    private var logSection: some View {
        Section {
            LabeledContent("Events", value: "\(controller.counts.total)")
            LabeledContent("Not sent", value: "\(controller.counts.pending)")

            Button(controller.isSyncing ? "Synchronizing…" : "Synchronize Now") {
                controller.synchronize()
            }
            .disabled(controller.isSyncing || !controller.isEnrolled)

            if let message = controller.lastSyncMessage {
                Text(message).foregroundStyle(.secondary)
            }
        } header: {
            Text("Log")
        } footer: {
            Text(
                backfillDone
                    ? "Changes sync on their own a moment after you make them, and whenever the app comes to the front."
                    : "Your existing data has not been imported into the log yet, so nothing syncs. Reopen the app to run the import."
            )
        }
    }

    /// The same code the portal shows the owner, so the two can be compared
    /// before approving. `claimed` and `waitingApproval` are two steps of one
    /// wait as far as this screen is concerned.
    private var matchingCode: String? {
        switch controller.enrollment {
        case let .claimed(code, _), let .waitingApproval(code, _): code
        default: nil
        }
    }

    private var statusText: String {
        switch controller.enrollment {
        case .notEnrolled: "Not connected"
        case .scanning, .openingLink: "Connecting…"
        case .claimed: "Waiting for approval"
        case .waitingApproval: "Approve in the browser"
        case .binding: "Binding the key…"
        case .enrolled: "Connected"
        case .revoked(.revokedByService): "Access revoked — enroll again"
        case .revoked(.credentialExpired): "Access expired — enroll again"
        case .revoked(.credentialUnusable): "Credential unusable — enroll again"
        case let .refreshError(failure): "Error: \(failure)"
        }
    }
}

#Preview {
    FTSyncView(controller: nil)
}
