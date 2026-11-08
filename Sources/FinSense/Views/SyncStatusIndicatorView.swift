// Sources/FinSense/Views/SyncStatusIndicatorView.swift
import SwiftUI

public struct SyncStatusIndicatorView: View {
    @ObservedObject public var syncService: CloudSyncService
    @ObservedObject public var authService = AuthService.shared
    @State private var isPopoverPresented: Bool = false

    public init(syncService: CloudSyncService) {
        self.syncService = syncService
    }

    public var body: some View {
        // Exibe o ícone APENAS se autenticado E com sync ativado
        if authService.isAuthenticated && syncService.isEnabled {
            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: syncService.syncStatus.iconSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)

                    if syncService.pendingMutationsCount > 0 && !syncService.isSyncing {
                        Text("\(syncService.pendingMutationsCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color(hex: "#F59E0B").opacity(0.2)))
                            .foregroundStyle(Color(hex: "#F59E0B"))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(syncService.syncStatus.statusDescription)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                SyncDetailPopoverContent(syncService: syncService)
            }
        }
    }

    private var iconColor: Color {
        switch syncService.syncStatus {
        case .disabled: return .secondary.opacity(0.6)
        case .synced: return Color(hex: "#10B981")
        case .syncing: return Color(hex: "#3B82F6")
        case .outOfSync: return Color(hex: "#F59E0B")
        case .authError: return Color(hex: "#EF4444")
        }
    }
}

public struct SyncDetailPopoverContent: View {
    @ObservedObject public var syncService: CloudSyncService

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: syncService.syncStatus.iconSymbol)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronização em Nuvem")
                        .font(.headline)
                    Text(syncService.syncStatus.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Alterações locais pendentes:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(syncService.pendingMutationsCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Text("Última sincronização:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.shortDate(lastSync))
                            .font(.caption)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    syncService.performSync()
                } label: {
                    if syncService.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("Sincronizando...")
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Sincronizar Agora")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncService.isSyncing || syncService.isSeeding || !syncService.canSync)
                .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
