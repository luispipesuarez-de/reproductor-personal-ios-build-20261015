import Foundation

enum AppError: Error, LocalizedError, Equatable {
    case offline, unavailable, resolutionFailed, storageFailed, invalidPlaylistName, invalidGenre, libraryIncompatible

    var errorDescription: String? {
        switch self {
        case .offline: return "Necesitas conexión a Internet. Intenta de nuevo."
        case .unavailable: return "Este contenido no está disponible en esta versión."
        case .resolutionFailed: return "No se pudo preparar este contenido. Intenta de nuevo."
        case .storageFailed: return "No se pudieron guardar los cambios. Intenta de nuevo."
        case .invalidPlaylistName: return "Escribe un nombre para la lista."
        case .invalidGenre: return "Escribe un género musical."
        case .libraryIncompatible: return "No se pudo abrir tu biblioteca. Tus datos no se han modificado."
        }
    }

    static func classify(_ error: Error) -> AppError {
        if let known = error as? AppError { return known }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
            .dataNotAllowed].contains(urlError.code) { return .offline }
        return .resolutionFailed
    }
}
